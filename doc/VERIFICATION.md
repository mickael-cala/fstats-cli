# fstats - journal de verification (sorties reelles)

> **Note (2026-08-26, post-restructuration)** : la compilation se fait depuis la
> racine : `fpc -O2 -Mobjfpc src\fstats.pas`.

## v2.16.2 — P2 vague 5 (2026-11-24) — P2 terminé

### 1. Égalités déterministes

Fichier `zebre abricot` ×2 : Top Words = `abricot` (2) puis `zebre` (2)
— ordre lexicographique aux fréquences égales (test 123 ; vérifié aussi
sur les chars : code point croissant). **Rupture documentée** : la matrix
golden v2.14.1 produisait `'ab'` avant `'a'` (égalités à 2) — v2.16.2
produit `'a'` avant `'ab'` : compteurs identiques, ordre contractuel
nouveau. Les suites sh/bat n'assertaient aucun ordre d'égalités :
**aucun test cassé** (61→62, 68→70 PASS, zéro nouveau FAIL).

### 2. --recursive : sémantique mesurée puis figée par tests

Arborescence f1.txt (racine) + sub/f2.txt + sub/f2.log + sub/deep/f3.txt :

| Commande | Fichiers | Observation |
|---|---|---|
| aucune | 4 | tout |
| `--include=*.txt` | 1 | `*` ne traverse pas `/` |
| `--include=**/*.txt` | 3 | récursif |
| + `--max-depth=1` | 2 | un niveau sous la racine |
| + `--exclude=sub/deep/*` | 2 | chemin RELATIF complet |

Test 122 en sh et bat : les cinq comptes vérifiés à chaque exécution.

### 3. État Périmètre P2 : TERMINÉ

Backlog §5 du registre : vagues 1 à 5 toutes traitées (corrigées ou
requalifiées ACCEPTÉ_DOCUMENTÉ avec justification). Restent au §6 les
décisions assumées, qui se lisent comme des limites, pas comme des dettes.

---

## v2.16.1 — P2 vague 4 (2026-11-24)

### 1. Options trompeuses : avant/après vérifiés

AVANT : `fstats --redact f.txt` → `Erreur: Fichier inaccessible ou
introuvable - --redact` (l'option traitée comme un fichier inexistant ;
l'utilisateur cherchait une panne disque). `--patern=x` (typo) : même
message. APRÈS : `l'option --redact exige une valeur (écriture :
--redact=VALEUR)` / `option inconnue : --patern=x [...] préfixez-le :
./--patern=x` — exit 1 dans les deux cas (vérifié).

### 2. Help top-lines : la vérité du code

`--top-lines=0` sur app.log : aucune section Top Lines (désactivée) ;
`--top-lines=3` : section à 3 lignes. Le help disait « 0 = tous » depuis la
v2.8.0 : corrigé dans le help ET dans SEMANTIQUE (qui répétait l'erreur).

### 3. Régressions

Fichiers normaux analysés sans `--` : inchangés (exit 0, `fstats fstats.exe`
fonctionne toujours — un fichier nommé `--x` DOIT désormais être préfixé,
rupture documentée). Vrai-faux positifs passés en revue : `--top-lines`
nu (légal, défaut 10), `-` (stdin), `--` jamais atteint car Length > 2.

Comptage : batch **68 PASS / 0 FAIL** ; run.sh 60 réussis / 65 échecs
node-dépendants (machine sans node, inchangé depuis la v2.14.1).

---

## v2.16.0 — P2 vague 3 (2026-11-24)

### 1. SHA-256 : implémentation validée à trois niveaux

- Vecteurs FIPS 180-4 : "abc" → `ba7816bf…015ad` ✓, chaîne vide →
  `e3b0c442…b855` ✓ (mini-programme de test dédié).
- Parité outil : `--summary-json tests/fixtures/test_fr.txt` émet
  `sha256: eba4cf176f…bb91` = `sha256sum` au caractère près (test 119,
  idem `Get-FileHash` côté Windows).
- Streaming : hash par blocs de 64 Ko, mémoire bornée (l'unité ne charge
  jamais le fichier).

### 2. Intégrité baseline : falsification attrapée

Baseline créée sur un fichier, fichier réécrit avec le MÊME nombre de
lignes/mots proches → check console `sha256 != 0 : FAIL (actual 1)` +
**exit 2** (avant : les métriques stables masquaient la dérive). Fichier
intact → check `sha256` ok, exit 0. Baseline pré-2.16.0 (sans clé) →
saut silencieux, rétrocompatible (vérifié en re-générant une baseline à
la main sans la clé).

### 3. Verdict console + hors-baseline visible

`--check --fail-if ...` → dernière ligne `Verdict : OK/ATTENTION/ECHEC —
exit N` (exit vérifié conforme). `--compare` + fichier absent de la
baseline → stderr `absent de la baseline : checks de derive ignores` +
ligne `N fichier(s) hors baseline` dans le verdict (avant : silence).

### 4. Bug --fail-on-delta inline (v2.6.0 → 2.16.0)

`fstats '--fail-on-delta=words>10' --compare=B --check f.txt` AVANT :
`Erreur: Fichier inaccessible ou introuvable - --fail-on-delta=words>10`
(l'option traitée comme fichier) ; forme espacée seule fonctionnait.
APRÈS : les trois formes (`=`, `:`, espace) fonctionnent — teste à la
main sur les trois formes + exit codes cohérents.

### 5. Exit code d'un check injecté

`--check --compare` sans autre check + hash divergent AVANT : FAIL
affiché, **exit 0** (gate conditionnée à Length(Checks)>0). APRÈS :
exit 2. La condition de gate compte tout check émis (ChecksEmitted).

### 6. Comptage des suites

run.bat : **66 PASS / 0 FAIL** (117-119 inclus). run.sh : 58 réussis /
65 échecs tous node-dépendants (node absent de la machine ; au passage :
le compteur node indépendant du test 48 confirme le comportement delta
sans node via le batch Windows, qui l'exécute nativement).

---

## v2.15.0 — P2 vague 2 (2026-11-24)

### 1. Match génériques : gel démontré, lineaire démontré

Ancien binaire v2.14.1 (conservé comme oracle) : fichier de **1 601 octets**
(préfixe `a`×1600 + `x`, une ligne) + `--pattern='*a*a*a*a*a*a*b'` →
**tué à timeout 20 s, CPU 100 %** (backtracking exponentiel). Nouveau
binaire v2.15.0 : même fichier → exit 0 **immédiat**. Pire cas construit
(ligne de 20 800 octets, pattern sans correspondance) → 1 s.

### 2. Boucle infinie match nul (hang, pas lenteur)

v2.14.1 : `--pattern='*'`, `--pattern='**'`, `--pattern='a||b'` (segment vide
d'alternance) → **boucle infinie** (match de longueur nulle, `StartPos`
n'avance jamais). v2.15.0 : `--json --pattern='*'` terminé, sortie
`"lines": 0, "matches": 0`. Test 114 (sh + bat).

### 3. Parité d'oracle (golden) : 23/23

37 sorties JSON de référence capturées avec le binaire v2.14.1 AVANT les
changements : 16 patterns `--pattern` (étoiles multiples, `?`, alternances,
adjacences `errorerrorerror`, casse, `|`), 9 patterns `--regex-tag`
(classes, quantifieurs imbriqués `A*B*C`, `[0-9]*[a-z]+`), `--mode=alarm`,
fixtures complètes + combinaison. La capture des patterns « gels » de
l'oracle s'est faite sous watchdog (3 patterns exclus de la comparaison :
`*`, `**`, `a||b` — leur oracle EST le gel, cf. §2). Rejouées après :
**23/23 identiques** après normalisation version/horodatage. L'algorithme
glouton min-d'abord reproduit l'ordre d'exploration de l'ancien DFS.

### 4. NFA tags : lineaire

`--regex-tag='a*a*a*b'` sur une ligne de 6 300 caractères : v2.15.0
immédiat (avant : backtracking). Test 115 (sh + bat). Sémantique
documentée : match le plus long depuis chaque position.

### 5. Ligne géante : métriques exactes, stockage borné

Ligne unique de 33 554 432 octets (`q` + LF) : `lines: 1`,
`characters: 33 554 433`, `line_max: 33 554 432` — **exacts**. Temps :
9 s (v2.14.1 : 16 s ; audit initial : 18 s avec concaténation
quadratique + 32 Mo conservés en mémoire). Append O(1) amorti
(tampon à croissance géométrique), stockage borné `LINE_STORE_MAX`
(65 536) / `WORD_STORE_MAX` (1 024). Test 116 (sh + bat) : ligne de
104 000 `q` → `line_max: 104000`, `characters: 104001`, `words: 1`.

### 6. Harnais Windows réparé : 63 PASS / 0 FAIL

Le run.bat committé en v2.14.1 **n'avait jamais tourné jusqu'au bout** :
- fins de ligne LF or cmd.exe exige CRLF → plantage parse au test 65+
  (« after66 » fantôme) ;
- `set C101_OK=1 || …` : l'**espace avant `&&` est inclus dans la valeur**
  (`"1 "` ≠ `"1"`) → 10 tests auto-sabotés (le mini-reproducteur affichait
  `C101_OK=[1 ]`) ;
- `echo words^>5` dans un pipe : le caret est re-parcouru par le cmd
  enfant → `>` devenait une redirection ; la ligne n'atteignait jamais le
  wizard, un fichier nommé `5` était créé sur disque (constaté) ;
- `\\\"` littéraux dans trois findstr : recherche d'une chaîne n'existant
  pas dans le JSON.

Après conversion CRLF + `set "X=1"` quotés + `^^^>` + findstr corrigés :
**63 PASS, 0 FAIL, RESULTAT atteint** (les tests node se skipent faute de
node sur la machine). run.sh : 55 réussis + 65 échecs **tous
node-dépendants** (absence de node, préexistants).

### 7. Compilation et comptage

`fpc -O2 -Mobjfpc -FE. src/fstats.pas` et `src/fcmd.pas` : OK.
`fstats --version` = `fstats 2.15.0` ; `fcmd --help` = `fcmd v2.15.0`.

---

## v2.14.1 — P2 vague 1 (2026-11-23)

### 1. Frontière de buffer 64 Ko (bug métrique CI)

Constat testé : préfixe de 65 535 'a' + `é` (séquence 2 octets à cheval) →
`invalid_utf8: 2` sur un fichier **valide** (le gate `--fail-if non_utf8>0`
rejetait un fichier sain selon son alignement). Correction : zone tampon
inter-blocs (octets restants portés en tête du bloc suivant ; orphelin de
fin de fichier toujours compté invalide).
Après : 6 alignements testés (65 530/65534/65535/65536/65537/65540) →
`invalid_utf8: 0` ; `invalid-utf8.bin` (vraie corruption) → 1, identique
avant/après ; `aaa\xC3` orphelin → 1. Test 111.

### 2. WARNING homologué

`printf 'WARNING disk full / WARN slow / ERROR bad'` + `--log-level` :
`Warn: 2` (avant : 1 — WARNING était classé `none`). `ERRORS` reste `none`
(test 86 inchangé). Test 113.

### 3. Formules CSV neutralisées

Ligne `=cmd|"/c calc"!A0 in log` + `--csv` : cellule exportée
`"'=cmd|""/c calc""!A0 in log"` — apostrophe préfixe (OWASP), Excel/Calc
voient du texte. Aucune cellule `=cmd` nue. Test 112.

### 4. Gate no-op + UX wizard + code mort

- `--check` sans check : stderr `Attention: mode check actif sans aucun
  check defini...`, exit 0 inchangé ; pas d'avertissement si un check existe.
- Wizard : numéros globaux affichés (`[29] --mode = alarm  (actif)`) ;
  entrée non numérique → `[?] entrez un numero de 0 a 7` + re-prompt
  (la session n'est plus avalée).
- Supprimé (code mort vérifié) : `OptModeAlarm`, `PrevWords/PrevChars/
  PrevSentences`, `BuildTopLinesJSON`. Batterie wizard 101-108 rejouée OK.

### 5. Parité

14 commandes vs v2.11.0 ; seuls diffs : horodatage des messages de check
(faux positif de batterie) et le masquage du Top Words avec `--redact`
(fix P1-3 voulu). Aucune fixture n'a de ligne commençant par `=` ni de
fichier > 64 Ko → pas de golden impacté.

`--version` = `fstats 2.14.1`. Comptage : run.sh = **115** report =
2 compilations + **113 tests**. Dogfood : exit 0.

## v2.14.0 — P1 sécurité (2026-11-23)

### 1. P1-1 : exécution par argv (plus de shell)

`RunAndWait` (ligne de commande assemblée, `FpSystem` = `sh -c` sous Unix)
remplacé par `RunArgs`/`RunTokens` (`SysUtils.ExecuteProcess` : fork/execve,
CreateProcess — l'OS reçoit un argv, aucun métacaractère n'est interprété).
Batterie wizard rejouée : 101-108 OK, exit 2 propagé (106), `--exec` OK (103b,
107). `fcmd` isolé (sans fstats à côté) : refus explicite exit 1, plus de
repli PATH silencieux. `CmdQuote` quotte les métacaractères pour l'affichage.

### 2. P1-2 : garde --out

Avant : `fstats f.txt --out=f.txt` → fichier vidé, exit 1 (perte de données).
Après : `Erreur: --out (...) designe un fichier analyse (...) - refus`,
exit 1, **fichier d'entrée intact** (vérifié par diff d'octets). Test 110.

### 3. P1-3 : redaction sans fuite

Avant : `--redact=email` sur un log contenant `jean.dupont@corp.example` →
l'email sortait en clair dans le Top Words (`'jean.dupont@corp.example' 3`).
Après : `'***'`. `RedactString` appliqué aux 11 points d'émission
(console words, JSON words/ngrams/tags ×3 formats, CSV words/tags).
Test 109 : grep `jean.dupont` = 0 occurrence sur console + JSON + CSV +
summary-json. Tests 74-77 (longest_lines, déjà couverts avant) inchangés.

### 4. Parité

17/17 commandes identiques au binaire v2.11.0 (hors périmètre des
correctifs). Seul diff voulu : avec `--redact`, un mot du Top Words
contenant une URL masquée (`***` au lieu de
`'https://internal.example.com...`). `--version` = `fstats 2.14.0`.
Comptage (recompté) : run.sh = **112** `report` = 2 compilations + **110
tests** (nouveau en 2.14.0 : 109 anti-fuite et 110 garde --out).

`--version` = `fstats 2.14.0`. Dogfood : exit 0.

## v2.13.1 — corrections P0 de l'audit croisé (2026-11-23)

Audit croisé dev × cyber × UX (trois auditeurs indépendants, constats
re-testés un par un). Corrections P0 vérifiées :

### 1. Off-by-one `--pattern` (fstats_lex.pas)

Avant : `fstats --pattern=error` sur `errorerrorerror` → `"matches": 2`.
Après : `"matches": 3` (convention `EndSi - Start`, alignée sur `MatchTagAt`).
Aucune occurrence adjacente dans les fixtures : tests golden existants
(matches=4/5/3/9) inchangés, parité 16/16 vs v2.11.0 confirmée.

### 2. Wizard générant des commandes refusées par fstats

Avant : profil corpus → `--ngrams=2,3` → `Erreur: --ngrams attend un entier
de 1 a 5` ; prompts `--csv-kind`/`--histogram=sentence_words` inexistants.
Après : profil corpus → `fstats --ngrams=2 --lexical-stats --readability
--json` — **exécutée** (exit 0). Prompt histogram corrigé en
`words_per_sentence`, `--csv-kind` → `--csv=summary|words|chars`.
Le test 103 exécute désormais la commande générée (103b).

### 3. Suite de tests structurellement rouge (depuis v2.12.0)

`run.sh:142`/`run.bat:136` grepaient `"2.11.0"` en dur. La version attendue
est maintenant **dérivée** de `src/fstats_types.pas` :
- sh : `PASS: --version affiche fstats 2.13.1 (derivation auto)`
- cmd.exe (bloc exact du run.bat rejoué) : `PASS: --version affiche fstats 2.13.1`

### 4. Divers

- `fcmd --profil=log|corpus|gate` accepté (le README le promettait).
- `--help` sans accents (promesse « ASCII pur »).
- Nouveaux tests : 103b (commande générée exécutée), 108/108b (occurrences
  adjacentes). Total : 110 vérifications dans run.sh (2 compiles + 108
  tests), équivalent dans run.bat.

`--version` = `fstats 2.13.1`. Dogfood : exit 0.

## v2.12.0 — split interne en unités (2026-11-23)

### 1. Compilation

`fpc -O2 -Mobjfpc -FE. src/fstats.pas` : exit=0

```
7081 lines compiled, 2.0 sec, 394272 bytes code, 19828 bytes data
```

Empreinte **identique** au mono-fichier v2.11.0 (394 272 / 19 828 octets).

### 2. Structure

`src/` = 8 unités à plat : `fstats.pas` (main seul, 1 444 lignes) +
`fstats_types` (338) + `fstats_utf8` (504) + `fstats_glob` (394) +
`fstats_lex` (1 229) + `fstats_analyzer` (820) + `fstats_checks` (829) +
`fstats_output` (1 523). La commande de compilation est inchangée : fpc
retrouve les unités dans `src/`.

### 3. Parité vs binaire pré-split (v2.11.0)

50 commandes comparées (sortie standard/err + exit code) : **toutes
identiques** — golden `test_fr.txt` (lignes 3, mots 13, caractères 72,
phrases 3), `--json` (ndjson/array/aggregate), `--summary-json`, `--csv`,
`--all`/`--char`/`--word`/`--line`, `--top-words`/`--top-chars`, `--ngrams`,
`--char-classes`, `--readability`, `--lexical-stats`, `--sentence-mode`,
`--word-mode`, `--case-fold`, `--max-unique`, `--mode=alarm`, `--pattern`,
`--top-lines`, `--redact`, `--log-level`, `--filter`, `--regex-tag`,
`--check`/`--fail-if`/`--warn-if` (exit 0/2/3), `--compare`/`--fail-on-delta`,
`--watch=0`, `--recursive`/`--include`/`--exclude`, glob direct `*.txt`,
`--no-color`/`--color`, `--quiet --out`, `--stdin`, `--help`, option
inconnue (exit 1), fichier absent (exit 1).

`--version` = `fstats 2.12.0`.

### 4. Doc croisée avec le code (2026-11-23)

- 47 options du `--help` : toutes présentes dans README.md et SEMANTIQUE.md.
- Métriques du gate (code `CanonMetricFailIf` = README : `lines`, `words`,
  `sentences`, `max_line_length`, `avg_words_per_sentence`/`avg_sentence_words`,
  `non_utf8`/`invalid_utf8`, `bom`, `crlf`, `tabs`, `nonprintable`).
- Exit codes 0/1/2/3 (`Halt(0..3)` dans le main = doc).
- 100 tests dans `tests/run.sh`/`run.bat` = CHANGELOG v2.11.0.
- Commande de compilation inchangée et valide partout (`wbld.bat`,
  `tests/run.*`, CI smoke, `doc/README.md`, GUIDE).
- Versions courantes passées à 2.12.0 dans README, `doc/README.md`,
  `doc/GUIDE-PEDAGOGIQUE.md`, `doc/SEMANTIQUE.md` (exemples `--version` et
  `"version"` des JSON d'exemple).
- Dogfood local (comme la CI) : `fstats --check --fail-if non_utf8>0
  --fail-if bom>0 --fail-if nonprintable>0 README.md CHANGELOG.md doc/*.md
  src/*.pas` → exit 0.

Genere le : 2026-08-26 11:56 - executable : `fstats.exe` (`fstats 2.2.0`)
Perimetre : increment A de ROADMAP-CIBLE1.md (stdin, glob interne,
recursivite, JSON multi-fichiers valide NDJSON/array/aggregate, `--summary-json`,
compteurs qualite). Les compteurs historiques sont inchanges vs v2.1.

## v2.13.0 — compagnon fcmd / --interactive (2026-11-23)

### 1. Compilation

`fpc -O2 -Mobjfpc -FE. src/fstats.pas` : exit=0 (1875 lignes)
`fpc -O2 -Mobjfpc -FE. src/fcmd.pas` : exit=0 (113 lignes)
`--version` = `fstats 2.13.0` ; `fcmd --help` = aide du compagnon.

### 2. Parité (hors --interactive)

22 commandes comparées vs binaire v2.11.0 (sortie + exit code, hors
`--help` qui gagne une ligne) : **toutes identiques** — golden test_fr.txt
3/13/72/3, JSON/CSV/aggregate, sentinel (alarm, pattern, redact, log-level,
regex-tag), checks+baseline, watch=0, recursive, glob, stdin, erreurs.

### 3. Wizard en pipe (tests 101-107 de run.sh/run.bat, rejoués ici)

- `fcmd --help` → exit 0, contient « compagnon ».
- `printf '2\n0\n' | fcmd --dry-run` → `fstats --mode=alarm --top-lines=10 --redact=email,ipv4,url`.
- `printf '4\n1\nf\ntests/fixtures/app.log\n2\n15\n2,3\n0\n' | fcmd --dry-run`
  → `fstats tests/fixtures/app.log --ngrams=2,3`.
- `printf '' | fcmd --dry-run` → exit 1 (EOF).
- `printf '3\n1\nf\ntests/fixtures/test_fr.txt\n0\nn\n' | fstats --interactive`
  → exit 0, commande affichée avec `--check`.
- `printf '3\n1\nf\ntests/fixtures/test_fr.txt\n5\n40\nwords>5\n0\no\n' | fstats --interactive`
  → **exit 2 propagé** (fail-if words>5 sur 13 mots).
- `printf '2\n1\nf\ntests/fixtures/alarms.log\n0\n' | fcmd --exec`
  → exit 0, fstats exécuté (sortie « Lines: »).

### 4. Dogfood

`fstats --check --fail-if non_utf8>0 --fail-if bom>0 --fail-if nonprintable>0
README.md CHANGELOG.md doc/*.md src/*.pas` → exit 0.

---

## 1. Compilation

`fpc -O2 -Mobjfpc fstats.pas` : exit=0
`2397 lines compiled, 0.9 sec, 318464 bytes code, 19460 bytes data`

## 2. Compteurs de reference (test_fr.txt) - inchanges vs v2.1

Attendu : lignes 3, mots 13, caracteres 72, phrases 3, moy. mots/phrase 4,
min/max/moy 16/30/23. Console (exit=0) :

```
File: test_fr.txt
Generated: 2026-08-26 11:34:44

Summary
-------
  Lines:               3
  Words:              13
  Characters:         72
  Sentences:           3
  Avg words/sentence:  4
  Line length:  min 16, max 30, avg 23
```

Note : pas de section `Quality` pour un fichier propre - la sortie console des
fichiers propres est strictement identique a celle de la v2.1.

## 3. Codes de retour (stdout/stderr separes)

| Cas | Exit | stdout | stderr |
|---|---|---|---|
| Succes : fstats test_fr.txt | 0 | donnees | (vide) |
| Fichier manquant : fstats absent.txt | 1 | (vide) | `Erreur: Fichier inaccessible ou introuvable - ...` |
| Aucun argument : fstats | 1 | (vide) | usage |
| --help | 0 | usage | (vide) |
| --version | 0 | `fstats 2.2.0` | (vide) |
| stdin + fichier : fstats - test_fr.txt | 1 | (vide) | message d'erreur |
| Glob sans correspondance : fstats 'nope/**/*.xyz' | 1 | (vide) | message d'erreur (gate CI jamais vide) |
| Conflit : --json --csv --out=x | 1 | (vide) | `Erreur: avec --out, choisissez seulement --json ou --csv.` |

## 4. stdin

`echo "un deux trois." | fstats - --json` : exit=0, objet JSON valide (parse node),
`"file": "stdin"`, `words: 3`, `sentences: 1`.

## 5. JSON multi-fichiers : NDJSON (defaut v2.2.0, corrige la concat v2.1)

`fstats tests\fixtures\bom.txt tests\fixtures\crlf.txt --json` : exit=0, 2 lignes
JSON, chacune parsee individuellement par node :

- ligne 0 : `bom=true`, `crlf=0` (fichier avec BOM UTF-8)
- ligne 1 : `bom=false`, `crlf=2` (fichier avec 2 fins de ligne CRLF)

## 6. --json-mode=aggregate

`fstats tests\docs\**\*.md --json-mode=aggregate` : exit=0, 3 fichiers trouves
par le glob recursif (`tests\docs\readme.md`, `guide\api.md`, `guide\usage.md`),
totaux = somme exacte des statistiques :

```
totals: files=3 lines=9 words=21 characters=123 sentences=3
```

## 7. --summary-json

`fstats --summary-json test_fr.txt` : exit=0, objet plat JSON valide (parse node) :

```json
{"file": "test_fr.txt", "tool": "fstats", "version": "2.2.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

## 8. Compteurs qualite (fixtures)

| Fixture | invalid_utf8 | bom | crlf | tabs | nonprintable |
|---|---|---|---|---|---|
| tests\fixtures\bom.txt | 0 | true | 0 | 0 | 0 |
| tests\fixtures\crlf.txt | 0 | false | 2 | 0 | 0 |
| tests\fixtures\tabs.txt | 0 | false | 0 | 2 | 0 |
| tests\fixtures\long-line.txt | 0 | false | 0 | 0 | 0 (line_max=177) |
| tests\fixtures\invalid-utf8.bin | 1 | false | 0 | 0 | 0 |

## 9. Sortie pipee : aucune sequence ANSI

Verification au niveau octet (recherche de ESC 0x1B) sur `fstats test_fr.txt`
pipe : aucune occurrence (attendu : aucune).

## 10. Suite de tests automatises

`tests\run.bat` (CMD, CI-friendly, sans Pause) : exit=0

```
PASS: compilation : fpc -O2 -Mobjfpc fstats.pas [exit 0]
PASS: test_fr.txt : 3/13/72/3, moy 4, min/max/moy 16/30/23
PASS: stdin : echo "un deux trois." | fstats - --json [words=3]
PASS: stdin + fichier : fstats - test_fr.txt -> exit 1 + message stderr
PASS: NDJSON : 2 fichiers -> 2 lignes parseables [bom=true, crlf=2]
PASS: aggregate : tests\docs\**\*.md -> 3 fichiers, totaux coherents
PASS: --summary-json test_fr.txt -> objet plat JSON valide
PASS: fixture invalid-utf8.bin : invalid_utf8 > 0 dans le JSON
PASS: fstats absent.txt -> exit 1, stdout vide, message stderr
PASS: glob sans correspondance -> exit 1 [gate CI jamais silencieusement vide]
PASS: sortie console pipee : aucune sequence ANSI [ESC]
PASS: --version affiche 2.2.0

RESULTAT : 12 reussi, 0 echec(s)
```

`tests/run.sh` : equivalent bash (meme jeux de cas).

## Conclusion

Increment A (v2.2.0) satisfait tous les criteres d'acceptation de
ROADMAP-CIBLE1.md : compilation propre, compteurs historiques inchanges,
stdin, glob/recursivite internes, JSON multi-fichiers valide (NDJSON par defaut,
array/aggregate), --summary-json, compteurs qualite, codes de retour 0/1
conserves en mode analyse, sortie ASCII pure en pipe.
---

## Increment C2-A « Lexique » (v2.3.0) — 2026-08-26

Validation de l'implementation de `doc/ROADMAP-CIBLE2.md` (C2-A : --word-mode,
--casefold, --lexical-stats, --top-words/--top-chars, --max-unique, CSV v2).
Binaire compile depuis `src/fstats.pas` (mono-fichier, RTL FPC standard).

### 1. Compilation

`fpc -O2 -Mobjfpc src/fstats.pas` : exit=0

```
2795 lines compiled, 1.2 sec, 326416 bytes code, 19492 bytes data
```

### 2. Regression par defaut (test_fr.txt, inchange)

`fstats --summary-json tests/fixtures/test_fr.txt` : 3/13/72/3, moy 4,
min/max/moy 16/30/23, memes champs (pas de cle lexicale sans --lexical-stats) :

```
{"file": "tests\/fixtures\/test_fr.txt", "tool": "fstats", "version": "2.3.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

### 3. --word-mode=ascii (corpus_en.txt, golden)

`fstats --summary-json --word-mode=ascii tests/fixtures/corpus_en.txt` :
`"words": 11` (ponctuation retiree : "Hello," -> "Hello", "test." -> "test").

### 4. --word-mode=unicode (corpus_fr.txt, golden)

`fstats --summary-json --word-mode=unicode tests/fixtures/corpus_fr.txt` :
`"words": 19` (la ponctuation et les apostrophes separent ; les accents
restent dans les mots).

### 5. --casefold (corpus_fr.txt)

`fstats --summary-json --lexical-stats --casefold=unicode tests/fixtures/corpus_fr.txt` :
`words=20, unique_words=16` — "Été" et "été" fusionnent (table basique).

`--casefold=none` : `unique_words=17` (casse conservee, "Été" != "été").

### 6. --lexical-stats (JSON)

`fstats --json --lexical-stats tests/fixtures/test_fr.txt` (exit=0, JSON parse
node) : bloc additif `"lexical"` apres `quality`, cles existantes inchangees,
`schema_version` reste "1.0" :

```
"lexical": { "unique_words": 12, "hapax": 11, "type_token_ratio": 0.923077,
             "average_word_length": 4.615385, "entropy_bits_per_word": 3.546594 }
```

Controles node : TTR = types/tokens (12/13), entropie dans [0, log2(12)].
Console (section dediee, ASCII pur) :

```
Lexical
-------
  Unique words:       17
  Hapax:              14
  Type-token ratio: 0.85
  Avg word length:  3.75
  Entropy:        4.0219
```

### 7. --top-words / --top-chars

`fstats --json --top-words=5 --top-chars=3 tests/fixtures/test_fr.txt` :
exactement 5 entrees `top_words` et 3 entrees `top_characters`.
`--top-words=0` : les 12 mots de test_fr.txt (0 = --all pour la section).

### 8. --max-unique (borne memoire)

`fstats --summary-json --lexical-stats --max-unique=5 tests/fixtures/test_fr.txt` :
`unique_words=5` (plafonne), `words=13` inchange, `average_word_length`
exact (accumule en streaming).

### 9. CSV v2 (rupture documentee)

En-tete exact et ligne summary avec colonne `file` :

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

`--csv=words` : meme en-tete, 10 lignes `word` (Top 10 par defaut) avec la
colonne `length` (code points). `--csv=chars` : colonne `code_point` remplie,
`length` = 1.

### 10. Options invalides et --version

`--word-mode=bogus` / `--max-unique=0` / `--csv=foo` : exit=1 + message
stderr francais. `fstats --version` : `fstats 2.3.0`.

### 11. Suites automatisees

`tests\run.bat` (CMD) : exit=0, 22/22 PASS. `tests/run.sh` (Git Bash) :
exit=0, 22/22 PASS — extraits :

```
PASS: --version affiche 2.3.0
PASS: --word-mode=ascii corpus_en.txt -> words=11 [golden]
PASS: --casefold=unicode corpus_fr.txt -> unique_words=16, words=20
PASS: --casefold=none corpus_fr.txt -> unique_words=17, casse conservee
PASS: --lexical-stats : champs presents, TTR=types/tokens, entropie bornee
PASS: --top-words=5 --top-chars=3 -> exactement 5 et 3 entrees
PASS: --top-words=0 -> tous les mots, 12 pour test_fr.txt
PASS: --max-unique=5 -> unique_words plafonne a 5, words=13 inchange
PASS: CSV v2 : en-tete exact, ligne summary avec colonne file, csv=words 10 lignes
PASS: --word-mode=unicode corpus_fr.txt -> words=19 [golden]
PASS: --word-mode=bogus -> exit 1 + message stderr

RESULTAT : 22 reussi, 0 echec(s)
```

### Bilan

C2-A satisfait les criteres de ROADMAP-CIBLE2.md : aucune regression en mode
par defaut (test_fr.txt 3/13/72/3, compteurs qualite, NDJSON/array/aggregate,
--summary-json, stdin, globs, exit codes 0/1, ASCII pur en pipe), nouvelles
options fonctionnelles et golden-teste, CSV v2 (rupture documentee) en place,
version 2.3.0. B et C (n-grams, histogrammes, lisibilite) restent a venir.
---

## Increment C2-B « Structure » (v2.4.0) — 2026-08-26

Validation de l'implementation de `doc/ROADMAP-CIBLE2.md` (C2-B : --ngrams,
--top-ngrams, --stopwords, --histogram, --char-classes, agregation).
Binaire compile depuis `src/fstats.pas` (mono-fichier, RTL FPC standard).

### 1. Compilation

`fpc -O2 -Mobjfpc src/fstats.pas` : exit=0

```
3577 lines compiled, 0.8 sec, 342128 bytes code, 19668 bytes data
```

### 2. Regression par defaut (test_fr.txt, inchange)

`fstats --summary-json tests/fixtures/test_fr.txt` : 3/13/72/3, moy 4,
min/max/moy 16/30/23, memes champs qu'en v2.3.0 sans les nouvelles options
(seule la version change) :

```
{"file": "tests\/fixtures\/test_fr.txt", "tool": "fstats", "version": "2.4.0", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

### 3. N-grams (goldens)

`fstats --json --ngrams=2 --word-mode=ascii tests/fixtures/corpus_en.txt` :
exactement **9 bigrammes** (comptes = 1), dont `hello world` ; le bigramme
traversant le saut de ligne `test one` est **absent** (les fenetres ne
traversent pas les lignes).

`fstats --json --ngrams=2 tests/fixtures/ngram_lines.txt` (fixture nouvelle
`alpha beta` / `gamma delta`) : **2 bigrammes** (`alpha beta`, `gamma delta`),
`beta gamma` **absent** — un bigramme n'apparaitrait que si les fenetres
traversaient le saut de ligne.

`fstats --json --ngrams=3 --top-ngrams=2 tests/fixtures/test_fr.txt` :
exactement **2 entrees** (top-K). `--ngrams=0` et `--ngrams=6` : exit=1 +
message stderr (`--ngrams attend un entier de 1 a 5`).

### 4. Stopwords

`fstats --json --ngrams=2 --top-ngrams=0 --stopwords=fr tests/fixtures/corpus_fr.txt` :
`words=20` (statistiques de mots inchangees) et **14 bigrammes** : `et`, `le`
et `Il` (casefold ascii -> `il`) sont retires du flux n-gram uniquement
(sans stopwords le fichier donne 16 bigrammes). Verifications : absence de
`et croissant,` et de `le garcon`, presence de `? est` (forme apres retrait
de `il`).

`--stopwords=fr` sans `--ngrams` : **ignore silencieusement** (exit=0, pas de
cle `ngrams` dans le JSON) — decision documentee au README.

### 5. Histogrammes (classes roadmap §6.6 + classes stables)

`fstats --json --histogram=line_length tests/fixtures/test_fr.txt` : classes
**identiques a l'exemple de la roadmap §6.6** `0-9, 10-19, 20-29, 30-39, 40+`,
comptes `0/1/1/1/0`, somme = lignes (3).

`--histogram=word_length` : classes stables `1-2, 3-4, 5-6, 7-8, 9-10, 11-12,
13+` (largueur 2), comptes `3/3/4/3/0/0/0`, somme = mots (13).

`--histogram=words_per_sentence` : classes stables `0-4, 5-9, 10-14, 15-19,
20+` (largueur 5, base 0), comptes `2/1/0/0/0`, somme = phrases (3).
Les formes a tirets de la roadmap (`--histogram=line-length`, `word-length`,
`words-per-sentence`) sont acceptees.

### 6. Char-classes (golden test_fr.txt)

`fstats --json --char-classes tests/fixtures/test_fr.txt` :

```
"char_classes": {"letters": 57, "digits": 0, "whitespace": 12,
                 "punctuation": 3, "control": 0, "other": 0}
```

Conservation : somme des six classes = 72 = `characters` (assertion de test).
Plages exactes documentees au README (« Semantique des classes de
caracteres »).

### 7. Agregation (--json-mode=aggregate)

`fstats tests\docs\**\*.md --json-mode=aggregate --char-classes --histogram=line_length` :
`char_classes` et `histogram` sommes classe par classe dans `totals` :

```
totals.char_classes: {"letters": 93, "digits": 0, "whitespace": 24,
                      "punctuation": 6, "control": 0, "other": 0}
totals.histogram: line_length ["0-9:3", "10-19:4", "20-29:2", "30-39:0", "40+:0"]
```

Les n-grams ne sont **pas** agreges (limitation documentee) : pas de cle
`ngrams` dans `totals`, ils restent par fichier dans `files`.

### 8. Options invalides et --version

`--ngrams=0` / `--ngrams=6` : exit=1 + message stderr. `--histogram=bogus` /
`--stopwords=bogus` : exit=1 + message stderr. `fstats --version` :
`fstats 2.4.0`.

### 9. Suites automatisees

`tests\run.bat` (CMD, exe racine via `-FE.`) : exit=0, **33/33 PASS**.
`tests/run.sh` (Git Bash, exe dans `src/`) : exit=0, **33/33 PASS** — extraits :

```
PASS: --ngrams=2 --word-mode=ascii corpus_en.txt -> 9 bigrammes, pas de [test one]
PASS: ngram_lines.txt -> 2 bigrammes, pas de [beta gamma]
PASS: --ngrams=3 --top-ngrams=2 -> exactement 2 entrees
PASS: --ngrams=0 / --ngrams=6 -> exit 1 + message stderr
PASS: --stopwords=fr --ngrams=2 corpus_fr.txt -> 14 bigrammes, mots vides retires
PASS: --histogram=line_length -> classes 0-9..40+, somme = lignes
PASS: --histogram=word_length -> somme des classes = mots
PASS: --histogram=words_per_sentence -> somme des classes = phrases
PASS: --char-classes test_fr.txt -> 57/0/12/3/0/0, somme = 72 caracteres
PASS: aggregate --char-classes --histogram -> totaux sommes classe par classe
PASS: sortie pipee ngrams+histogram+char-classes : aucune sequence ANSI

RESULTAT : 33 reussi, 0 echec(s)
```

### Bilan

C2-B satisfait les criteres de ROADMAP-CIBLE2.md : aucune regression en mode
par defaut (les 22 cas v2.3.0 passent inchanges, version 2.4.0), n-grams
(goldens, non-traversee des lignes, top-K borne, stopwords fr/en), histogrammes
(classes roadmap §6.6 + classes stables documentees, somme = ligne/mots/phrases),
char-classes (conservation = characters, golden), agregation classe par classe,
exit codes 0/1, ASCII pur en pipe. C2-C (lisibilité, optionnel) livré en
v2.5.0 — voir section 10 ci-dessous.

---

## 10. Increment C2-C — lisibilite (v2.5.0)

Date : 2026-08-26. Ajout de `--readability` (4 metriques + score 0-100 sans
syllabes, formule figee dans SEMANTIQUE.md), bump `FSTATS_VERSION` 2.4.0 →
2.5.0, nouvelle fixture `tests/fixtures/empty.txt` (0 octet).

### 10.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas` : exit=0 (`3736 lines compiled`).

### 10.2 Valeurs de reference (test_fr.txt, mode raw par defaut)

Attendu (recalcul independant node) : ASL = 13/3 = 4.333333 ;
ALW = 60/13 = 4.615385 ; longs = 3 tokens >= 7 (`exemple`, `simple.`,
`Deuxieme`) = 23.076923% ; score =
100*(1-(0.5*min(4.333333/30,1)+0.5*min((4.615385-3)/5,1))) = 76.623932.

`fstats --readability --summary-json tests\fixtures\test_fr.txt` : exit=0,
`avg_sentence_words: 4.333333`, `avg_word_chars: 4.615385`,
`pct_long_words: 23.076923`, `readability_score: 76.623932` — verifie par
node (epsilon 0.001) sur les 4 valeurs.

Console : `Avg sentence words:4.3333 / Avg word chars: 4.6154 /
Pct long words:23.0769% / Score (0-100): 76.6239`.

`--word-mode=ascii` : `Avg word chars: 4.3077`, `Pct long words: 7.6923%`,
score 79.7009 (`Deuxieme` → `deuxi` + `me`).

### 10.3 Cas limites et combinaisons

- Fichier vide (`empty.txt`) : toutes les metriques a 0, score 0, aucun NaN
  (division par zero protegee).
- `--readability --json` : bloc `readability` avec les 4 cles.
- `--readability --lexical-stats` : blocs `lexical` ET `readability`
  presentes (clés plates en summary-json).
- `--readability --csv` : 4 lignes `summary,,avg_sentence_words/avg_word_chars/
  pct_long_words/readability_score,,<v>,`.
- `--json-mode=aggregate` : readability par fichier, PAS dans `totals`
  (comme les n-grams).
- Sortie pipee `--readability` : aucune sequence ANSI.

### 10.4 Suites automatisees

`tests\run.bat` : exit=0, **39/39 PASS**. `tests/run.sh` : exit=0, **39/39
PASS**. Les 33 cas precedents passent inchanges (aucune regression du mode
par defaut : test_fr.txt 3/13/72/3, moy 4, min/max/moy 16/30/23).

### Bilan

C2-C satisfait les criteres de ROADMAP-CIBLE2.md : metriques sur le mode
courant, formule exacte documentee et fgee, pas de Flesch-Kincaid exact
(mentionne au README), score borne [0,100], aucun NaN sur fichier vide,
additif en JSON/CSV, ASCII pur, 39/39 sur les deux suites. Cible 2
**complete**.

---

## 11. Cible 1 B+C — moteur de checks et baseline (v2.6.0)

Date : 2026-08-26. Ajout de `--check`, `--fail-if`, `--warn-if`, `--compare`,
`--fail-on-delta` (mode check, exit 0/1/2/3), bump `FSTATS_VERSION` 2.5.0 →
2.6.0. Alias `invalid_utf8` accepte en plus de `non_utf8` (nom JSON du
summary). Correction d'encodage de doc/ROADMAPFULL.md (mojibake -> UTF-8).

### 11.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas` : exit=0 (4906 lignes compilees,
362592 octets code). Warnings : uniquement generics.dictionaries (RTL, preexistants).

### 11.2 Exit codes (verifies par node spawnSync, exit reels)

| Commande | Exit | Statut |
|---|---|---|
| `--check --fail-if lines>2 test_fr.txt` (3 lignes) | 2 | FAIL (actual 3) |
| `--check --fail-if lines>5 test_fr.txt` | 0 | OK (actual 3) |
| `--check --warn-if lines>2 test_fr.txt` | 3 | WARN (actual 3) |
| `--check --fail-if lines>1 absent.txt` | 1 | erreur fatale (prime) |
| `--fail-if lines>5 test_fr.txt` (sans --check) | 0 | mode check implicite |
| `--check --fail-if lines>2 --json test_fr.txt` | 2 | `{"id":"lines","metric":"lines","actual":3,"op":">","threshold":2,"status":"fail"}` |

### 11.3 Baseline / derive

`--summary-json` capturee dans bl_test.json, puis `--compare bl_test.json
--fail-on-delta lines>10 test_fr.txt` : exit 0 (`delta lines > 10% : OK (delta
0%)`). Baseline modifie (`"lines": 3` -> `"lines": 1`) : exit 2 (`FAIL (delta
200%)`). `--fail-on-delta` sans `--compare` : exit 1 + stderr (`--fail-on-delta
exige --compare BASELINE`).

### 11.4 Dogfood CI (etape ajoutee a ci.yml, validee localement)

`fstats --check --fail-if non_utf8>0 --fail-if bom>0 --fail-if nonprintable>0
README.md doc\*.md src\fstats.pas` : exit 0, 10 fichiers analyses (commande
exacte du workflow, glob `doc\*.md` sous cmd).

### 11.5 Suites automatisees

`tests\run.bat` : exit=0, **56/56 PASS**. `tests/run.sh` : exit=0, **56/56
PASS**. Les 39 cas precedents passent inchanges (aucune regression du mode
par defaut : test_fr.txt 3/13/72/3).

### Bilan

Cible 1 **complete** (A v2.2.0, B+C v2.6.0) : moteur de checks (grammaire
figee, 10 metriques + alias, statuts ok/warn/fail, exit 0/1/2/3, mode analyse
non rompu), baseline NDJSON + derive en % (base=0 documentee), section
Checks console + bloc checks JSON (id stables), dogfood CI, 56/56 sur les
deux suites.

---

## 12. Correctif v2.6.1 — les decimales 3.14 ne cloturent plus une phrase

Date : 2026-08-26. Limite connue traitee : un point decimal (`3.14`) comptait
comme fin de phrase. Corrections : `FSTATS_VERSION` 2.6.0 → 2.6.1, logique de
cloture differee dans `AnalyzeData` (`DotPending`/`LastCP`, procedure imbriquee
`CloseSentence`), nouvelles fixtures `tests/fixtures/decimal.txt` et
`tests/fixtures/decimal_end.txt`, 3 nouveaux cas (57-59) dans les deux suites.

### 12.1 Regle figee (verifiee par node)

- `Le prix est 3.14 euros. Bravo !` → **2 phrases** (avant : 3), 7 mots.
- `Le prix est 3.14` (fin de flux) → **1 phrase** (avant : 2).
- `Version 3. Fin.` → **2 phrases** (le point apres `3` suivi d'un espace
  cloture toujours).
- `3 . 14. Fin.` → **3 phrases** (point entoure d'espaces = fin de phrase).
- `3.14. 5. Fin.` → **3 phrases** (point entre chiffres ignore, point final
  apres `4` cloture).
- Regression : test_fr.txt reste 3 phrases (3/13/72/3).
- Histogramme words_per_sentence : somme des classes = phrases (2 sur
decimal.txt).

### 12.2 Suites automatisees

`tests\run.bat` : exit=0, **59/59 PASS**. `tests/run.sh` : exit=0, **59/59
PASS**. Les 56 cas precedents passent inchanges.

### Bilan

Correctif verifie : aucun NaN, aucune regression, sémantique figee dans
SEMANTIQUE.md (point entre deux chiffres ≠ fin de phrase ; point apres
chiffre suivi d'un espace = fin de phrase ; point espace = fin de phrase).

## 13. v2.7.0 - --sentence-mode=basic|smart

Verifie le : 2026-08-26 22:55 - executable : `fstats.exe` (`fstats 2.7.0`)

### 13.1 Regle figee du mode smart (verifiee par node, stdin)

- `M. Dupont est la. Bravo.` : smart → **2 phrases** (le point de `M.` est
  avale), basic → **3 phrases** (comportement historique inchange).
- `Visitez https://ex.com maintenant.` : smart → **1 phrase** (le point de
  `.com` est avale : `://` dans la fenetre des 8 derniers caracteres),
  basic → **2 phrases**.
- `e.g. ceci.` : smart → **1 phrase** (les deux points de `e.g.` avales :
  premier par la regle de prefixe `e.` vers `e.g`, second par
  correspondance exacte `e.g`).
- `Coût 3.14 euros.` : smart → **1 phrase** (regle decimale v2.6.1
  conservee en smart).
- `www.ex.com ici.` : smart → **2 phrases** (limite documentee : seul le
  premier point de `www.` est protege, celui de `.com` cloture).
- `--sentence-mode=bogus` : exit=1, stderr ASCII pur
  `Erreur: --sentence-mode attend "basic" ou "smart" (recu "bogus")`.
- `--sentence-mode=SMART` et `--sentence-mode:smart` : acceptes (casse
  insensible, `=` et `:`).
- Regression : test_fr.txt sans option reste 3 phrases (3/13/72/3) ;
  `--sentence-mode=basic` explicite donne le meme resultat.

### 13.2 Suites automatisees

`tests\run.bat` : exit=0, **67/67 PASS**. `tests/run.sh` : exit=0, **67/67
PASS**. Les 59 cas precedents passent inchanges (seul le cas 12
`--version` est passe de 2.6.1 a 2.7.0).

### Bilan

La §6.3 du ROADMAPFULL (detection de phrases) est traitee : decimales
(v2.6.1, mode par defaut), abréviations et URLs (v2.7.0, mode smart,
perimetre documente dans SEMANTIQUE.md). Le plan `--sentence-mode` a trois
valeurs de la roadmap a ete simplifie a deux (`none` ecarte : ne pas
compter les phrases n'apporte rien).

---

## 14. Cible 3-A — Log Sentinel : patterns, top-lines, redaction (v2.8.0)

Date : 2026-11-23. Ajout de `--pattern=TEXTE` (littéral + `|` + `*`/`?`,
insensible à la casse, occurrences non chevauchantes), `--top-lines=N`
(lignes identiques groupées, top-K borné comme les n-grams) et
`--redact=email,ipv4,url` (remplace par `***` dans les sorties seulement,
compteurs sur le brut). Bump `FSTATS_VERSION` 2.7.0 → 2.8.0. Nouvelles
fixtures `tests/fixtures/app.log` (9 lignes log avec niveaux ERROR/WARN/INFO,
lignes dupliquées, email/IP/URL) et `tests/fixtures/redact.txt`.

### 14.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas` : exit=0 (`5900 lines compiled`).

### 14.2 Patterns (golden app.log)

- `--pattern=ERROR` → `{"pattern":"ERROR","lines":4,"matches":4}` (4 lignes ERROR).
- `--pattern='ERROR|WARN'` → 5 lignes / 5 matches (4 ERROR + 1 WARN, alternance).
- `--pattern='*timeout*'` → 3/3 (wildcard des deux côtés, substring match).
- `--pattern='*'` → 9/9 (toutes les lignes).
- stdin : `echo -e "ERROR x\nINFO ok\nERROR y" | fstats - --summary-json --pattern=ERROR`
  → `lines=2, matches=2`.

### 14.3 Top-lines (golden app.log)

- `--top-lines=2` → 2 entrées, top 1 = `2026-01-15 10:00:05 ERROR connection timeout to db.internal` (count=2),
  top 2 = `2026-01-15 10:00:12 INFO health check OK` (count=2).
- stdin `aaa\nbbb\naaa` + `--top-lines=5` → top 1 = `aaa` count=2.
- Tri : fréquence décroissante, puis alphabétique (déterministe).

### 14.4 Redaction (golden redact.txt)

- `--redact=email,ipv4,url` → `longest_lines[0].content` =
  `Contact *** or visit *** from ***` (email, URL, IPv4 masqués).
- `--redact=email` seul → email masqué, `10.0.0.1` conservée.
- `--redact=ipv4` seul → IPv4 masquée, email conservé.
- `--redact=url` seul → URL masquée, email conservé.
- Compteurs sur le brut : `characters=195` inchangé (la redaction n'affecte
  que les sorties).

### 14.5 Options invalides

- `--redact=bogus` → exit 1, stderr `Erreur: --redact attend "email", "ipv4" ou "url"`.
- `--top-lines=abc` → exit 1, stderr `--top-lines attend un entier >= 0`.
- `--pattern=` (vide) → exit 1, stderr `--pattern : valeur vide`.

### 14.6 Non-régression et ANSI

- `test_fr.txt` : 3/13/72/3, moy 4, min/max/moy 16/30/23 (inchangé).
- Sortie pipée `--pattern --top-lines --redact` : aucune séquence ANSI (ESC).
- JSON C3-A complet parseable (patterns + top_lines + redact dans longest_lines).

### 14.7 Suites automatisées

`tests\run.bat` / `tests\run.sh` : 82 cas (67 existants + 15 nouveaux C3-A),
`--version` attendu `2.8.0`. (Validation node non exécutée localement ici —
node absent de l'environnement ; cas vérifiés manuellement un par un.)

### Bilan

C3-A satisfait les critères de ROADMAP-CIBLE3.md : matcher interne documenté
(littéral + `|` + `*`/`?`, PAS une regex complète), top-lines borné (comme les
n-grams), redaction post-comptage (compteurs sur le brut), exports console/JSON/
CSV/summary-json, exit codes 0/1 conservés, ASCII pur en pipe. C3-B (niveaux),
C3-C (alarm) et C3-D (watch) restent à venir.

---

## 15. Cible 3-B — niveaux de log + filtre (v2.9.0)

Date : 2026-11-23. Ajout de `--log-level` (détection ERROR>WARN>INFO>DEBUG>TRACE,
mot entier insensible à la casse, somme = lines) et `--filter=niveaux` (filtre
l'affichage console des lignes, compteurs sur tout le fichier). Bump
`FSTATS_VERSION` 2.8.0 → 2.9.0. Nouvelle fixture `tests/fixtures/levels.log`
(8 lignes avec tous les niveaux + pièges ERRORS/mot entier).

### 15.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas` : exit=0 (`~6060 lines compiled`).

### 15.2 Niveaux (golden levels.log)

`--log-level levels.log` → `error=2, warn=1, info=1, debug=1, trace=1, none=2`.
- `ERRORS not a level word` → `none` (mot entier : ERRORS ≠ ERROR).
- `error lowercase counts too` → `error` (insensible à la casse).
- Somme = 8 = lines.

`--log-level app.log` → `error=4, warn=1, info=4, debug=0, trace=0, none=0`,
somme = 9 = lines.

### 15.3 Priorité et mot entier (stdin)

- `WARN then ERROR here` → `error=1, warn=0` (priorité ERROR > WARN).
- `ERRORS everywhere` → `none=1` (pas de match mot entier).

### 15.4 Filtre (console)

- `--log-level --filter=error --top-lines=5 app.log` → Top Lines ne contient que
  les lignes ERROR (rangs renumérotés 1, 2).
- `--filter=error,warn levels.log` → ERROR + WARN affichés, pas INFO.
- `--filter=bogus` → exit 1, stderr `--filter attend "error", ...`.
- Compteurs globaux inchangés (lines=9 sur app.log malgré le filtre).

### 15.5 Non-régression et ANSI

- `test_fr.txt` : 3/13/72/3 (inchangé).
- Sortie pipée `--log-level --filter` : aucune séquence ANSI.
- JSON `log_levels` présent en pretty/NDJSON/summary-json ; lignes `loglevel` en CSV.

### 15.6 Suites automatisées

`tests\run.bat` / `tests\run.sh` : 90 cas (82 + 8 nouveaux C3-B), `--version`
attendu `2.9.0`.

### Bilan

C3-B livré : détection de niveaux figée (mot entier, priorité, somme=lines),
filtre d'affichage console, exports JSON/CSV/summary, non-régression OK.
C3-C (alarm/SCADA) et C3-D (watch) restent à venir.

---

## 16. Cible 3-C — alarm : regex-tag + mode=alarm (v2.10.0)

Date : 2026-11-23. Ajout du mini-moteur `--regex-tag=PATTERN` (littéral +
classes `[...]` + quantifieurs `? * +`, extraction non chevauchante) et du
raccourci `--mode=alarm` (= `--log-level` + `--top-lines` + `--regex-tag`
avec défaut `[A-Z]+[0-9]+`). Bump `FSTATS_VERSION` 2.9.0 → 2.10.0. Nouvelle
fixture `tests/fixtures/alarms.log` (9 lignes SCADA avec PLC1/MOTOR23/PLC2/SENSOR7).

### 16.1 Compilation

`fpc -O2 -Mobjfpc -FE. src\fstats.pas` : exit=0.

### 16.2 Tags (golden alarms.log)

- `--regex-tag='PLC[0-9]+'` → `PLC1` count=5, `PLC2` count=1.
- `--regex-tag='[A-Z]+[0-9]+' --top-tags=10` → PLC1=5, MOTOR23=2, PLC2=1, SENSOR7=1.
- `--top-tags=2` → exactement 2 entrées (PLC1, MOTOR23).
- Quantifieur `+` : stdin `PLC sans chiffre\nPLC42 ok` → seul `PLC42` extrait.

### 16.3 Mode alarm

`--mode=alarm alarms.log` → `log_levels` (error=3, warn=2, info=3) +
`top_lines` + `tags` (PLC1=5 en tête). Pattern défaut `[A-Z]+[0-9]+`.

### 16.4 Options invalides

`--top-tags=abc`, `--mode=bogus`, `--regex-tag=` (vide) → exit 1 + stderr.

### 16.5 Non-régression

- `test_fr.txt` : 3/13/72/3 (inchangé).
- Sortie pipée `--mode=alarm` : aucune séquence ANSI.
- 97 cas dans run.sh/run.bat, `--version` = `2.10.0`.

### Bilan

C3-C livré. C3-D (watch/follow en polling) reste à venir.

---

## 17. Cible 3-D — watch/follow en polling (v2.11.0) — **Cible 3 COMPLÈTE**

Date : 2026-11-23. Ajout de `--watch`/`--follow` + `--interval=N` (défaut 2 s,
min 1) : boucle de polling qui ré-analyse le fichier à chaque tick et affiche
`[timestamp] lines=N (+delta) words=N chars=N sentences=N | error=… …`.
Handler Ctrl+C cross-platform (SetConsoleCtrlHandler Windows / FpSignal
SIGINT+TERM Linux) → arrêt propre exit 0. Bump `FSTATS_VERSION` 2.10.0 → 2.11.0.

### 17.1 Watch (vérifié avec timeout 4 s, interval 1)

`--watch --interval=1 --log-level app.log` → 5 statuts :
`[ts] lines=9 (+0) words=65 chars=540 sentences=7 | error=4 warn=1 info=4 none=0`

### 17.2 Delta positif (fichier qui grandit)

Watch en arrière-plan + `echo "…ERROR new alarm on PLC9" >> watch_test.log`
→ tick suivant : `lines=10 (+1) … error=5` (delta et niveau mis à jour).

### 17.3 Restrictions

- `--watch -` (stdin) → exit 1, stderr.
- `--watch a.log b.log` (2 fichiers) → exit 1, stderr.
- `--interval=0` → exit 1, stderr.

### 17.4 Non-régression

- `test_fr.txt` : 3/13/72/3 (inchangé). 100 cas dans run.sh/run.bat,
  `--version` = `2.11.0`.

### Bilan

**Cible 3 complète** : C3-A (patterns/top-lines/redaction) + C3-B (log-level/
filter) + C3-C (alarm/regex-tag) + C3-D (watch). fstats v2.11.0 = text profiler
+ quality gate + log sentinel, toujours mono-fichier (6 795 lignes), zéro
dépendance, ASCII pur, exit codes stables.
