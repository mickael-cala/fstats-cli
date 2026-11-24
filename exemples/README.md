# Exemples — corpus de démonstration de fstats / Demonstration corpus for fstats

> 🇫🇷 **Français** : ce dossier contient des fichiers réalistes et volontairement
> piégeux pour explorer `fstats` et son compagnon `fcmd`. Chaque compteur cité
> ci-dessous a été **vérifié sur ces fichiers exacts** (pas d'invention) avec la
> v2.16.2. Toutes les commandes se lancent depuis la racine du dépôt.
>
> 🇬🇧 **English**: this folder contains realistic — and deliberately tricky —
> files to explore `fstats` and its companion `fcmd`. Every count quoted below
> was **verified against these exact files** (nothing invented) with v2.16.2.
> All commands are meant to be run from the repository root.

---

## 1. Inventaire / Inventory

| Fichier / File | Ce qu'il illustre / What it exercises |
|---|---|
| `logs/app-multi-niveaux.log` | Les 6 niveaux de log, la priorité `ERROR > WARN`, le piège ERROR**S**, les tabulations |
| `logs/scada-alarmes.log` | Tags d'alarmes industriels (`PLC1`, `MOTOR23`, `SENSOR7`…) pour `--regex-tag`, `--mode=alarm`, `--top-tags` |
| `logs/apache-access.log` | Format combiné Apache : IPs pour `--redact=ipv4`, emails pour `--redact=email`, URLs pour `--redact=url` |
| `logs/syslog-melange.log` | Syslog RFC3164 : niveaux mélangés, échecs `sshd`, `--log-level` |
| `textes/corpus-fr.txt` | Français réel (accents, ligatures), abréviations (`M.`, `e.g.`, `i.e.`), décimales `3.14`, email+URL pour `--redact`, `--sentence-mode=smart` |
| `textes/corpus-en.txt` | Équivalent anglais (`Mr.`, `e.g.`, `i.e.`, `Cafés naïfs`) — même pièges, autre langue |
| `textes/unicode-monde.txt` | Grec, cyrillique, latin étendu, **jumeaux NFC/NFD** (`cafe\u0301` vs `café`), U+FFFD |
| `donnees/clients.csv` | CSV avec quotes, virgules, accents, emails, IPs, URLs — `fstats` le lit comme texte brut |
| `donnees/evenements.ndjson` | NDJSON (JSON par ligne) — `--json-mode=ndjson`, `--pattern` sur du texte structuré |
| `cas-limites/bom-utf8.txt` | BOM UTF-8 véritable (EF BB BF) → `bom: true` |
| `cas-limites/utf8-abime.txt` | Octets UTF-8 invalides réels → `invalid_utf8: 4` |
| `cas-limites/frontiere-64kio.txt` | 65 535 × `a` + `é` qui **chevauche la frontière de buffer 64 Ki** → `invalid_utf8: 0` (correctif v2.14.1 en action) |
| `cas-limites/fins-de-ligne-melangees.txt` | LF + CRLF + CR isolé + dernière ligne sans saut |
| `cas-limites/controles-non-imprimables.txt` | `\x01`, tabulations, espaces insécables/sévères |
| `cas-limites/vide.txt` | Fichier vide → `lines: 0`, sortie saine |
| `cas-limites/ascii-pur.txt` | ASCII pur — zéro octet > 0x7F |
| `arborescence/` | 6 fichiers imbriqués (`rapport.txt`, `notes.log`, `journal.txt`, `sous/archive.log`, `sous/lisible.md`, `sous/deep/fiche.txt`) : `--recursive`, `--include`, `--exclude`, `--max-depth` |
| `baselines/corpus-fr-baseline.txt` | Baseline `--summary-json` du corpus FR : sert de référence à `--compare` + `--fail-on-delta`, et porte le `sha256` |

## 2. Premiers pas vérifiés / Verified first steps

Comptes réels mesurés sur ces fichiers (v2.16.2) / Real counts measured on these
exact files:

| Commande / Command | Résultat vérifié / Verified result |
|---|---|
| `fstats exemples/logs/app-multi-niveaux.log --log-level` | `error=4, warn=2, info=4, debug=1, trace=2, none=0` (somme = 13 = lignes) |
| `fstats exemples/logs/scada-alarmes.log --regex-tag='PLC[0-9]+' --top-tags=10` | Tags : `PLC1=3`, `PLC2=2`, `PLC3=1` |
| `fstats exemples/logs/apache-access.log --redact=email,ipv4,url --top-lines=3` | Top Lines avec `***` à la place de chaque IP |
| `fstats exemples/textes/corpus-fr.txt --summary-json` | `lines: 7, words: 95, characters: 593, sentences: 17` |
| `fstats exemples/textes/corpus-fr.txt --sentence-mode=smart --summary-json` | `sentences: 12` (34 au lieu de 0 !) |
| `fstats exemples/textes/corpus-en.txt --summary-json` | `lines: 7, words: 82, characters: 532, sentences: 16` |
| `fstats exemples/cas-limites/bom-utf8.txt --summary-json` | `bom: true`, `invalid_utf8: 0` |
| `fstats exemples/cas-limites/utf8-abime.txt --summary-json` | `invalid_utf8: 4` (2 octets isolés + 2 octets d'une séquence tronquée) |
| `fstats exemples/cas-limites/frontiere-64kio.txt --summary-json` | `invalid_utf8: 0` — le `é` à cheval sur les 64 Ki est décodé intact |
| `fstats exemples/cas-limites/vide.txt --summary-json` | `lines: 0` — pas de division par zéro, moyenne fixée à 0 |
| `fstats exemples/cas-limites/fins-de-ligne-melangees.txt --summary-json` | `lines: 4, crlf: 1` (LF, CRLF, CR et dernière ligne nue) |

### 🇫🇷 Trois subtilités que ces fichiers illustrent (à savoir avant de s'étonner)

1. **La ligne `ERRORS` compte quand même comme `error`… parce que la phrase
   contient aussi le mot `error`** dans « ne comptera pas comme niveau error ».
   Le niveau est détecté **par mot entier, n'importe où dans la ligne** — la
   détection ne sait pas que vous parlez DU niveau plutôt que vous ne l'utilisez.
   (`ERRORS` seul ne matche pas : mot entier ≠ préfixe.)
2. **La priorité figée** : la ligne `DEBUG ... WARN then ERROR ...` compte comme
   `error`, pas `debug` — le premier trouvé dans l'ordre `ERROR > WARN > INFO >
   DEBUG > TRACE` gagne.
3. **Smart mode** : `Version 3. du logiciel...` clôture une phrase en basic
   (chiffre + point + lettre), `3.14` ne clôture jamais, `e.g.`/`i.e.`
  Prototype avancés, `M. Dupont` avalé. D'où l'écart 17 → 12 phrases.

### 🇬🇧 Three subtleties these files showcase (know before you wonder)

1. **The `ERRORS` line still counts as `error`… because the sentence also
   contains the word `error`** in « ne comptera pas comme niveau error ». Levels
   are detected as **whole words, anywhere in the line** — the detector cannot
   tell that you are *mentioning* a level rather than *emitting* one.
    (`ERRORS` alone does not match: whole word ≠ prefix.)
2. **Frozen priority**: the line `DEBUG ... WARN then ERROR ...` counts as
   `error`, not `debug` — first hit in the order `ERROR > WARN > INFO > DEBUG >
   TRACE` wins.
3. **Smart mode**: `Version 3. du logiciel...` closes a sentence in basic mode
   (digit + period + letter), `3.14` never closes, `e.g.`/`i.e.` periods are
   swallowed, `M. Dupont` is absorbed. Hence the 17 → 12 sentence gap.

## 3. Multifichiers et filtres / Multi-file and filters

Réseau de 6 fichiers vérifié / Verified 6-file tree:

| Commande / Command | Fichiers / Files |
|---|---|
| `fstats exemples/arborescence --recursive=exemples/arborescence --summary-json` | 6 (tout) |
| `fstats --recursive=exemples/arborescence --include='*.txt' --summary-json` | 2 (`*` ne traverse pas `/`) |
| `fstats --recursive=exemples/arborescence --include='**/*.txt' --summary-json` | 3 |
| `fstats --recursive=exemples/arborescence --include='**/*.txt' --max-depth=1 --summary-json` | 2 (un niveau sous la racine) |
| `fstats --recursive=exemples/arborescence --include='**/*.txt' --exclude='sous/deep/*' --summary-json` | 2 |

## 4. La gate CI sur des vrais fichiers / The CI gate on real files

```bash
# 1) Générer une baseline (référence) depuis le corpus FR :
fstats exemples/textes/corpus-fr.txt --summary-json > ma-baseline.txt

# 2) Comparer plus tard : identique -> exit 0 (vérifié) :
fstats exemples/textes/corpus-fr.txt --compare exemples/baselines/corpus-fr-baseline.txt --fail-on-delta 'words>10'
# -> exit 0, verdict OK

# 3) Gate simple qui échoue (vérifié) : scada-alarmes.log = 10 lignes > 5 :
fstats exemples/logs/scada-alarmes.log --check --fail-if 'lines>5'
# -> Verdict : ECHEC ... exit 2

# 4) Falsification : modifiez une ligne du corpus FR puis relancez (2) :
#    le sha256 de la baseline refuse de suivre -> check sha256 FAIL, exit 2.
```

Le fichier `baselines/corpus-fr-baseline.txt` embarque le `sha256` du corpus
(v2.16.0) : toute retouche du fichier source est détectée même si les métriques
sont inchangées — c'est l'intégrité, pas seulement la dérive.

The committed baseline carries the corpus `sha256` (v2.16.0): any edit of the
source file trips the gate even when every metric is unchanged — integrity,
not just drift.

## 5. Le compagnon fcmd sur ces exemples / The fcmd companion on these files

🇫🇷 Séquences de réponses **vérifiées** — tapez-les quand le wizard pose sa
question, ou pipez-les (`printf '3\n1\nf\n…' | fcmd --dry-run`).
🇬🇧 **Verified** answer sequences — type them when the wizard asks, or pipe
them.

**Scénario A — profil « gate » sur les alarmes SCADA :**

```bash
printf '3\n1\nf\nexemples/logs/scada-alarmes.log\n5\n40\nlines>3\n0\n' \
  | fcmd --dry-run
# Commande générée (vérifiée) :
#   fstats --check --json --summary-json exemples/logs/scada-alarmes.log "--fail-if=lines>3"
```

**Scénario B — profil « log » avec extraction de tags :**

```bash
printf '2\n1\nf\nexemples/logs/scada-alarmes.log\n4\n34\nPLC[0-9]+\n0\n' \
  | fcmd --dry-run
# Commande générée (vérifiée) :
#   fstats --mode=alarm --top-lines=10 --redact=email,ipv4,url \
#     exemples/logs/scada-alarmes.log --regex-tag=PLC[0-9]+
```

🇫🇷 Numéros du menu : 1=Fichiers (f=ajouter), 2=Analyse, 4=Sentinel,
5=Checks ; options 34=`--regex-tag`, 40=`--fail-if`, 42=`--compare`. Le
wizard ré-affiche la commande à chaque étape — c'est la **dernière** ligne
qui compte. Essayez aussi `fstats --interactive` (mêmes questions, exécution
proposée en fin de parcours avec « o »).

🇬🇧 Menu numbers: 1=Files (f=add), 2=Analysis, 4=Sentinel, 5=Checks; options
34=`--regex-tag`, 40=`--fail-if`, 42=`--compare`. The wizard re-prints the
command at every step — the **last** one is the final command. Also try
`fstats --interactive` (same questions, offers to run the command with « o »).

## 6. Limites documentées / Documented limits

- 🇫🇷 `textes/unicode-monde.txt` contient des jumeaux visuels
  (**NFD vs NFC**) volontaires : les compteurs qualité restent vrais sur ce
  qu'ils mesurent (aucun octet invalide), mais la détection d'homoglyphes
  malveillants (ex. `Е` cyrillique dans `ERROR`) est **hors périmètre** —
  voir `doc/AUDIT-SECURITE.md` §6 (requalifié ACCEPTÉ-documenté).
- 🇬🇧 `textes/unicode-monde.txt` contains deliberate visual twins
  (**NFD vs NFC**): the quality counters stay true to what they measure (no
  invalid bytes), but malicious homoglyph detection (e.g. Cyrillic `Е` inside
  `ERROR`) is **out of scope** — see `doc/AUDIT-SECURITE.md` (fr) §6
  (requalified accepted-and-documented).
