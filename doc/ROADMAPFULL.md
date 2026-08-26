## Verdict rapide et pourquoi cette roadmap !

`fstats` est déjà un **bon outil CLI** : propre, portable, simple, JSON/CSV, sortie ASCII sûre pour redirection.
Mais aujourd’hui, ce n’est pas encore une *killer app* : c’est un **analyseur descriptif**. Il dit : “voilà combien de lignes, mots, caractères, phrases”.

Pour devenir une killer app, il doit passer de :

> “je compte des statistiques”

à :

> “je détecte, compare, contrôle et bloque des problèmes sur du texte/logs/corpus”.

Le positionnement gagnant :

> **fstats — text profiler & quality gate for files, logs and corpus.**

En clair : un outil capable d’analyser du texte, mais surtout de servir dans des scripts, CI, audits de logs, QA documentaire, analyse de corpus, éventuellement logs SCADA/PLC.

---

# 1. Qui va l’employer ?

Voici les utilisateurs les plus réalistes.

| Persona | Ce qui t’intéresse | Ce que `fstats` doit t'apporter |
|---|---|---|
| **DevOps / SRE / admin système** | Analyser des logs, détecter anomalies, intégrer dans CI/monitoring | stdin, NDJSON, seuils, diff, watch, exit codes |
| **Développeurs CLI / scripting** | Outil rapide, portable, sans dépendance, sortie JSON exploitable | binaire statique, `--json`, `--csv`, exit codes stables |
| **Technical writers / localization** | Qualité de documentation, longueur de phrases, volume de mots | lisibilité, stats par fichier, comparaison avant/après |
| **Data scientists / NLP débutant** | Explorer rapidement un corpus texte | top words, n-grams, vocabulaire, entropy, export CSV/JSON |
| **Enseignants / étudiants** | Montrer Unicode, parsing, stats texte, CLI | aide claire, exemples, tests, comportement prévisible |
| **Ingénierie industrielle / SCADA / PLC** | Analyser alarmes, journaux, tags, récurrences | mode logs, regex, top patterns, export CSV/JSON |
| **Utilisateurs Termux / Linux ARM64** | Petit outil texte puissant sans dépendances | binaire statique, cross-compilable, faible empreinte |

Le plus gros potentiel n’est pas “remplacer `wc`”.
Le plus gros potentiel est : **audit textuel automatisé**.

---

# 2. Ce qui est déjà fort dans fstats (selon moi)

Il faut garder ces points.

### Points forts actuels

1. **Sortie console ASCII pure**
   - Excellent pour logs, redirection, CI, terminals anciens, SCADA.
   - Ne pas sacrifier ça.

2. **JSON / CSV**
   - Très bon choix pour intégration avec `jq`, pandas, PowerShell, Grafana, scripts.

3. **Multiplateforme Free Pascal**
   - Un seul binaire, peu de dépendances, portable Windows/Linux/ARM/Termux.

4. **Sémantique documentée**
   - Très important. Tu expliques comment mots/phrases sont comptés.
   - C’est rare et précieux pour un outil de mesure.

5. **Codes de retour**
   - Indispensable pour scripts. À enrichir proprement.

6. **Compacité**
   - `fstats` doit rester simple à installer et rapide à exécuter.

---

# 3. Pourquoi ce n’est pas encore une killer app

Parce qu’il manque trois dimensions décisives.

## A. Il ne décide pas

Un outil killer doit pouvoir dire :

- OK / PAS OK
- seuil dépassé
- différence par rapport à une baseline
- anomalie détectée

Exemple :

```sh
fstats docs/*.md --check --fail-if avg_sentence_words>25
```

Si la phrase moyenne est trop longue, exit code non nul.

---

## B. Il ne compare pas assez

Une killer app doit pouvoir dire :

- ce fichier a changé par rapport à avant
- le corpus a grossi
- le nombre d’erreurs dans les logs a augmenté
- la longueur de ligne a dérivé

Exemple :

```sh
fstats diff baseline.json current.log
```

---

## C. Il ne s’intègre pas encore assez aux pipelines

Pour devenir indispensable, il doit accepter :

- stdin
- flux compressés
- listes de fichiers
- glob patterns
- récursivité
- NDJSON
- aggregation multi-fichiers

Exemple :

```sh
find /var/log -name '*.log' -print0 | fstats --stdin-list --json
```

ou :

```sh
cat app.log | fstats - --json
```

---

# 4. Le positionnement killer recommandé

C'est faire de `fstats` non pas un simple “word counter”, mais un outil en 3 modes :

---

## Mode 1 — Text Quality Gate (un couteau suisse mais sans les lames !)

Pour documentation, rapports, fichiers texte, traduction.

Cas d’usage :

- vérifier qu’un fichier texte n’est pas vide
- vérifier que la longueur moyenne de ligne n’explose pas
- vérifier le nombre de phrases
- vérifier l’encodage UTF-8
- vérifier absence de BOM ou CRLF non désiré
- comparer deux versions

Commandes souhaitées :

```sh
fstats report.txt --check
fstats docs/**/*.md --fail-if avg_line_length>120
fstats docs/*.md --fail-if non_utf8=1
fstats report.txt --compare baseline.json
```

Exit codes possibles :

| Code | Sens |
|---:|---|
| 0 | succès, checks OK |
| 1 | erreur fatale : fichier introuvable, option invalide, etc. |
| 2 | check échoué |
| 3 | warnings seulement |

---

## Mode 2 — Corpus Profiler (pour évaluer le niveau de bullshit d'un document, si si. Et avec l'IA en mode RAG local ==> merci Fstats !)

Pour analyse de texte, linguistique, NLP, documentation.

Cas d’usage :

- top mots
- top caractères
- n-grams
- richesse lexicale
- entropie
- histogramme de longueur de ligne
- distribution de phrases
- export pour pandas/R/Excel

Commandes souhaitées :

```sh
fstats corpus/*.txt --aggregate --json
fstats corpus/*.txt --top-words 100
fstats corpus/*.txt --ngrams 2
fstats corpus/*.txt --lexical-stats
fstats corpus/*.txt --histogram=line_length
```

Sortie JSON idéale :

```json
{
  "schema_version": "1.0",
  "files_count": 12,
  "totals": {
    "lines": 4300,
    "words": 35000,
    "characters": 210000,
    "sentences": 1400
  },
  "top_words": [],
  "top_bigrams": [],
  "lexical": {
    "unique_words": 4300,
    "hapax": 1800,
    "type_token_ratio": 0.123
  }
}
```

---

## Mode 3 — Log Sentinel (t'as déja dépanné un SCADA genre System Platform ? Ou analysé les logs d'un PLC Rockwell/AB ? moi oui ... En fait tu souffres !!!)

Pour logs applicatifs, logs SCADA, logs d’automates, alarmes.

Cas d’usage :

- compter lignes ERROR/WARN/INFO
- top messages
- top tags
- top codes d’erreur
- détecter lignes anormalement longues
- détecter erreurs UTF-8
- exporter vers CSV/JSON/Grafana
- surveiller un fichier en temps réel

Commandes souhaitées :

```sh
fstats app.log --log-level
fstats alarms.log --pattern 'ALARM|ERROR|WARN'
fstats scada.log --regex-tag 'TAG[0-9]+'
fstats app.log --watch
fstats app.log --ndjson --out=app.stats.ndjson
```

Exemple de sortie :

```json
{
  "file": "app.log",
  "lines": 9823,
  "errors": 43,
  "warnings": 112,
  "top_messages": [
    {"rank": 1, "count": 43, "value": "timeout on device"},
    {"rank": 2, "count": 18, "value": "retry connection"}
  ]
}
```

Pour SCADA/PLC, tu pourrais même ajouter un mode :

```sh
fstats alarms.log --mode=alarm
```

avec extraction :

- timestamp
- sévérité
- tag
- message
- count par tag
- count par sévérité
- intervalles de temps anormaux

---

# 5. Modifications prioritaires — P0

Ce sont les modifications les plus importantes. Sans elles, pas de killer app.

---

## 5.1. Ajouter stdin

Aujourd’hui, beaucoup d’outils CLI vivent dans des pipelines.

Il faut supporter :

```sh
cat file.txt | fstats -
cat file.txt | fstats --stdin
git diff | fstats -
```

Priorité : **très haute**.

---

## 5.2. Corriger la sortie JSON multi-fichiers

Dans la doc :

> `--out` avec plusieurs fichiers concatène les exports : préférer un export par fichier pour du JSON exploitable.

C’est un point à corriger pour une vraie adoption.

Il faut proposer :

```sh
fstats a.txt b.txt --json
```

avec plusieurs stratégies :

### Option 1 : NDJSON / JSON Lines

Une ligne JSON par fichier :

```sh
fstats *.txt --json --json-mode=ndjson
```

Sortie :

```json
{"file":"a.txt","lines":10,...}
{"file":"b.txt","lines":44,...}
```

Avantages :

- parfait pour logs
- parfait pour `jq -c`
- parfait pour streaming

### Option 2 : tableau JSON

```sh
fstats *.txt --json --json-mode=array
```

Sortie :

```json
[
  {"file":"a.txt", ...},
  {"file":"b.txt", ...}
]
```

### Option 3 : objet global avec aggregation

```sh
fstats *.txt --json --json-mode=aggregate
```

Sortie :

```json
{
  "files": [ ... ],
  "totals": { ... },
  "top_words": [ ... ]
}
```

Recommandation :

- par défaut : un fichier = objet JSON
- plusieurs fichiers : NDJSON
- `--json-mode=array` pour compatibilité outillage
- `--json-mode=aggregate` pour analyse de corpus

---

## 5.3. Ajouter glob et récursivité

Sous Windows, le shell ne fait pas toujours l’expansion de glob.
Sous Linux, c’est le shell, mais un outil peut être plus puissant.

Il faut :

```sh
fstats "*.txt"
fstats "**/*.md"
fstats --recursive ./docs
fstats --include "*.log" --exclude "*.gz"
```

Options suggérées :

```sh
--recursive
--glob
--include=PATTERN
--exclude=PATTERN
--max-depth=N
--files-from=LISTE
```

Très important pour usage PowerShell/CMD/CI.

---

## 5.4. Ajouter aggregation multi-fichiers

Actuellement, l’usage naturel serait :

```sh
fstats *.txt
```

Mais pour une killer app, il faut deux niveaux :

1. stats par fichier
2. stats globales du corpus

Options :

```sh
fstats *.txt --per-file
fstats *.txt --aggregate
fstats *.txt --summary-only
```

JSON recommandé :

```json
{
  "schema_version": "1.0",
  "generated": "...",
  "options": {},
  "files": [
    {"file": "a.txt", "statistics": {}}
  ],
  "totals": {
    "files": 2,
    "lines": 100,
    "words": 900,
    "characters": 5000
  },
  "top_words": []
}
```

---

## 5.5. Ajouter vrais exit codes de check

Aujourd’hui :

| Code | Signification |
|---:|---|
| 0 | succès |
| 1 | erreur |

Pour CI, il faut distinguer :

| Code | Signification |
|---:|---|
| 0 | OK |
| 1 | erreur fatale |
| 2 | seuil/check échoué |
| 3 | warnings |

Exemple :

```sh
fstats report.txt --fail-if lines=0
```

ou :

```sh
fstats report.txt --fail-if avg_line_length>120
```

Si seuil dépassé :

```text
CHECK FAILED: avg_line_length=145 > max=120
exit code: 2
```

---

## 5.6. Ajouter `fstats check`

C’est probablement LA feature killer.

Exemple :

```sh
fstats check report.txt --config fstats.toml
```

ou version simple :

```sh
fstats report.txt \
  --fail-if lines<1 \
  --fail-if words<10 \
  --fail-if avg_sentence_words>30 \
  --fail-if non_utf8>0
```

Autre syntaxe possible :

```sh
fstats check report.txt \
  --min-lines 1 \
  --min-words 10 \
  --max-avg-sentence-words 30 \
  --require-utf8
```

Exemples de checks utiles :

```sh
--min-lines N
--max-lines N
--min-words N
--max-words N
--min-sentences N
--max-avg-line-length N
--max-line-length N
--max-avg-sentence-words N
--require-utf8
--forbid-bom
--forbid-crlf
--forbid-tabs
--max-invalid-utf8 N
--max-nonprintable N
```

C’est ce qui transforme l’outil en outil de CI. ALLEZ ... check !

---

## 5.7. Ajouter comparaison / baseline

Très utile pour QA et logs.

Workflow :

```sh
fstats report.txt --json --out baseline.json
# modification du fichier
fstats report.txt --compare baseline.json
```

Sortie :

```text
Metric           Baseline   Current   Delta
lines            27         31        +4
words            170        190       +20
characters       976        1040      +64
sentences        7          8         +1
avg_words        24         23        -1
```

Options :

```sh
--compare=baseline.json
--fail-on-delta lines>10%
--fail-on-delta words>20%
```

---

## 5.8. Ajouter diagnostics d’encodage

`fstats` dit : UTF-8 uniquement. Il faut donc devenir excellent sur ce point. Mais pas que

Ajouter :

```sh
--diagnostics
--strict-utf8
--on-invalid-utf8=error|replace|skip
--show-invalid-offsets
--max-errors=N
```

Rapport souhaité :

```json
{
  "encoding": {
    "utf8_valid": false,
    "invalid_sequences": 3,
    "bom": false,
    "newline_style": "LF",
    "control_characters": 2,
    "replacement_characters": 0
  }
}
```

Très utile pour :

- logs corrompus
- exports SCADA
- fichiers Windows avec encoding douteux (OUPS !)
- OCR
- fichiers générés par automates (pas industriel ...)

---

## 5.9. Ajouter détection binaire

Un fichier texte peut contenir des octets binaires.

Il faut éviter de produire des stats absurdes. C'est mieux !

Options :

```sh
--on-binary=error|skip|force
```

Par défaut :

```text
fstats: file appears to be binary, use --force-text to analyze anyway
exit code: 1
```

---

## 5.10. Ajouter `--quiet`, `--verbose`, `--debug`

Actuellement `--quiet` existe pour éviter confirmation. Il faut une politique claire (enfin) :

- stdout : données
- stderr : erreurs, warnings, diagnostics
- `--quiet` : seulement erreurs fatales
- `--verbose` : informations supplémentaires
- `--debug` : détails internes

---

# 6. Modifications importantes — P1

Ces features ne sont pas indispensables le premier jour, mais elles feront passer l’outil de “bon” à “vraiment utile”. Un peu comme une carriére pro ?!?

---

## 6.1. Top words amélioré

Actuellement, la ponctuation collée fait partie du mot. C’est documenté, mais limitant. (on va régler cela juste avant la phase 3 Do not panic !)

Il faut proposer plusieurs modes.

### Modes suggérés

```sh
--word-mode=raw
--word-mode=ascii
--word-mode=unicode
--word-mode=regex
```

Exemples :

```sh
fstats file.txt --word-mode=ascii
```

- `raw` : comportement actuel
- `ascii` : mots ASCII seulement, ponctuation retirée
- `unicode` : tentative de segmentation Unicode
- `regex` : définition personnalisée

Exemple :

```sh
fstats file.txt --word-regex '[A-Za-zÀ-ÖØ-öø-ÿ0-9_]+'
```

Très utile pour :

- logs
- code source
- tags SCADA
- identifiants
- langues non anglaises

---

## 6.2. Unicode case folding

Actuellement : minuscules ASCII seulement.

Pour analyse de corpus, il faudrait :

```sh
--casefold=ascii|unicode|none
```

Exemple :

```text
École, école, ÉCOLE
```

Peut devenir équivalent si `--casefold=unicode`.

Attention : Unicode case folding est complexe.
Commencer simple : ASCII, puis option Unicode basique. Recette du succés.

---

## 6.3. Améliorer la détection de phrases

La doc mentionne (pour línstant):

> Un point décimal (`3.14`) clôture donc une phrase.

C’est acceptable, mais il faut offrir un mode plus intelligent.

Options :

```sh
--sentence-mode=basic
--sentence-mode=smart
--sentence-mode=none
```

Modes :

- `basic` : `.`, `!`, `?`, `…`
- `smart` : essaie d’éviter décimales, abréviations, URLs
- `none` : ne pas compter phrases

Exemple :

```sh
fstats rapport.txt --sentence-mode=smart
```

---

## 6.4. Ajouter statistiques lexicales

Très utile pour corpus/NLP.

Ajouter :

```sh
--lexical-stats
```

Métriques :

- unique words
- hapax legomena : mots apparaissant une seule fois
- type-token ratio
- top words
- top n-grams
- entropy approximative
- average word length

Exemple JSON :

```json
{
  "lexical": {
    "total_word_tokens": 1200,
    "unique_word_types": 350,
    "hapax": 120,
    "type_token_ratio": 0.2917,
    "average_word_length": 5.4,
    "entropy_bits_per_word": 8.1
  }
}
```

---

## 6.5. Ajouter n-grams

Feature très puissante.

```sh
fstats corpus.txt --ngrams 1
fstats corpus.txt --ngrams 2
fstats corpus.txt --ngrams 3
```

Exemple :

```text
Top Bigrams
-----------
 1  "the file"     12
 2  "file is"       9
 3  "is missing"    7
```

Options :

```sh
--ngrams=2
--top-ngrams=50
--stopwords=fr|en|none
```

Pour logs SCADA :

```sh
fstats alarms.log --ngrams 3
```

Peut révéler :

```text
"motor over temperature"
"connection timeout plc2"
"sensor value out range"
```

---

## 6.6. Ajouter histogrammes

Très utile en terminal ASCII.

```sh
fstats file.txt --histogram=line-length
fstats file.txt --histogram=words-per-sentence
fstats file.txt --histogram=word-length
```

Sortie ASCII :

```text
Line length histogram
---------------------
  0-9   ###
 10-19  ##########
 20-29  ################
 30-39  ######
 40+    #
```

---

## 6.7. Ajouter character classes

Au-delà des top caractères, donner classes :

```sh
fstats file.txt --char-classes
```

Sortie :

```text
Character Classes
-----------------
  letters       512
  digits         74
  spaces        143
  punctuation    88
  control         4
  unicode        12
```

JSON :

```json
{
  "character_classes": {
    "letters": 512,
    "digits": 74,
    "whitespace": 143,
    "punctuation": 88,
    "control": 4,
    "other": 12
  }
}
```

---

## 6.8. Ajouter lisibilité

Pour documentation, rapports, qualité rédactionnelle.

```sh
fstats report.txt --readability
```

Métriques possibles :

- Flesch Reading Ease
- Flesch-Kincaid Grade Level
- Gunning Fog
- Pour français : Kandel-Moares ou adaptation Flesch-fr

Exemple :

```text
Readability
-----------
  flesch_reading_ease: 62.4
  flesch_kincaid_grade: 8.1
  average_sentence_words: 17.2
  average_syllables_per_word: 1.6
```

Attention : syllabes en français/anglais non trivial.
Commencer par metrics simples :

- mots par phrase
- caractères par mot
- pourcentage mots longs
- score simple basé sur longueur de phrase/mot

---

## 6.9. Ajouter redaction / privacy

Très utile pour logs.

```sh
fstats app.log --redact=email,ip,url,token
```

Objectif : ne pas afficher ou compter clairement des données sensibles dans les exemples.

Exemple :

```text
Top Lines
---------
  12  User ***@example.com failed login
```

Options :

```sh
--redact=email
--redact=ipv4
--redact=ipv6
--redact=url
--redact=secret
--redact-regex=PATTERN
```

---

## 6.10. Ajouter rapports Markdown / HTML

La sortie console reste prioritaire, mais un rapport humain aide.

```sh
fstats corpus/*.txt --md --out=report.md
fstats corpus/*.txt --html --out=report.html
```

HTML simple, sans JavaScript, ou avec très peu. (Vote for "sans")

Mais attention : ne pas devenir une usine à gaz.

---

# 7. Features avancées — P2

À ne faire qu’après avoir solidifié le cœur.

---

## 7.1. Mode watch

```sh
fstats --watch app.log
```

Affiche stats en direct :

```text
lines: 10234
errors: 12
warnings: 55
last update: 10:42:11
```

Options :

```sh
--watch
--interval=2
--follow
```

---

## 7.2. Mode tail / filter

```sh
fstats app.log --filter ERROR --tail
```

ou :

```sh
fstats app.log --grep ERROR --count
```

---

## 7.3. Patterns et regex

```sh
fstats app.log --pattern ERROR
fstats app.log --pattern 'timeout|failed|denied'
fstats alarms.log --regex 'PLC[0-9]+'
```

JSON :

```json
{
  "patterns": [
    {"pattern": "ERROR", "matches": 43, "lines": 41},
    {"pattern": "timeout", "matches": 12, "lines": 12}
  ]
}
```

---

## 7.4. Mode logs structuré

Pour logs semi-structurés :

```sh
fstats app.log --parse 'timestamp level message'
```

ou :

```sh
fstats alarms.csv --mode=csv --columns timestamp,severity,tag,message
```

C’est très pertinent pour SCADA/PLC.

Exemple :

```sh
fstats alarms.log --mode=alarm --json
```

Sortie :

```json
{
  "alarms_total": 123,
  "by_severity": {
    "critical": 3,
    "error": 12,
    "warning": 34,
    "info": 74
  },
  "top_tags": [
    {"tag": "PLC1", "count": 22},
    {"tag": "MOTOR3", "count": 9}
  ]
}
```

---

## 7.5. Export SQLite / DuckDB / Parquet ?

Pour plus tard.

```sh
fstats corpus/*.txt --sqlite=stats.db
```

Mais au début, JSON/CSV suffisent.

---

## 7.6. Plugins / scripting

Possible mais risqué.

Exemple :

```sh
fstats file.txt --plugin=mycheck.lua
```

Mais cela complexifie beaucoup TROP.
Je ne ferais pas avant d’avoir une base solide. Mais j'ai nanobasic ...

---

# 8. Ce qu’il faut améliorer dans la sortie actuelle

## Console

La sortie console est bonne, mais il faudrait :

### Ajouter mode machine-friendly

```sh
fstats file.txt --summary-only
```

Sortie compacte :

```text
lines=27 words=170 chars=976 sentences=7 avg_words_per_sentence=24 line_min=7 line_max=68 line_avg=35
```

Très pratique pour scripts shell :

```sh
eval "$(fstats file.txt --summary-env)"
echo "$FSTATS_LINES"
```

ou :

```sh
fstats file.txt --summary-json
```

---

## JSON

Ajouter :

```json
{
  "tool": "fstats",
  "version": "2.2.0",
  "schema_version": "1.0",
  "file": "demo.obm",
  "generated": "..."
}
```

Important pour compatibilité future.

---

## CSV

Le CSV actuel est trop spécialisé :

```csv
metric,rank,value,code_point,count
```

Pour usage sérieux, il faudrait soit plusieurs CSV, soit un format plus clair.

### Option long format

```csv
file,type,rank,value,code_point,count,length
demo.txt,character,1," ",U+0020,143,
demo.txt,word,1,print,,9,
demo.txt,line,1,,, ,68
demo.txt,summary,,,,
```

Mais ce n’est pas idéal.

### Recommandation ?

Ajouter :

```sh
--csv=long
--csv=summary
--csv=chars
--csv=words
--csv=lines
```

ou produire plusieurs fichiers :

```sh
fstats file.txt --csv --out=stats
```

produit :

```text
stats.summary.csv
stats.characters.csv
stats.words.csv
stats.lines.csv
```

---

# 9. Packaging : aussi important que les features

Une killer app n’est pas seulement une bonne idée.
C’est aussi un outil très facile à installer.

---

## 9.1. Binaires à publier

Publier dans GitHub Releases :

- `fstats-windows-x64.exe`
- `fstats-windows-x86.exe`
- `fstats-windows-arm64.exe`
- `fstats-linux-amd64`
- `fstats-linux-arm64`
- `fstats-termux-arm64` si possible, je vais essayer mais avec la libc ANDROID ...
- `fstats-darwin-amd64`
- `fstats-darwin-arm64`

Avec :

- checksums SHA256
- tags semver
- changelog clair (je vois bien GEMINI PRO pour m'aider)

---

## 9.2. Installation

Idéalement :

### Windows

```powershell
winget install fstats
scoop install fstats
choco install fstats
```

### Linux

Selon distro :

```sh
apt install fstats
dnf install fstats
```

Au minimum : téléchargement binaire statique.

### Termux

Très intéressant pour mon profil de developpeur sous termux ou termux/proot-distro (via SSH parce que mon PC de bureau n'est pas toujours avec moi) :

```sh
pkg install fstats
```

ou script :

```sh
curl -L https://example.com/fstats-termux-arm64 -o $PREFIX/bin/fstats
chmod +x $PREFIX/bin/fstats
```

---

## 9.3. Shell completion

À ajouter :

```sh
fstats --completion bash
fstats --completion zsh
fstats --completion fish
fstats --completion powershell
```

Ou :

```sh
fstats completions bash > /etc/bash_completion.d/fstats
```

---

## 9.4. Documentation

Une killer app a une documentation orientée tâches, sans jeux de mots.

Sections recommandées :

- Quick start
- Installation
- Examples by use case
- JSON schema
- CSV format
- Exit codes
- CI integration
- Recipes
- Known limitations
- Verification / testing

Exemples de recettes :

```sh
# Vérifier un fichier Markdown
fstats doc.md --fail-if avg_line_length>120

# Comparer deux versions
fstats old.txt --json > old.json
fstats new.txt --compare old.json

# Analyser logs
fstats app.log --pattern ERROR --json

# Aggréger un corpus
fstats corpus/*.txt --aggregate --json
```

---

# 10. CI / GitHub Action : énorme levier (oui mais faire windows-latest avec freepascal et des script cmd/powershell + node  : insomnie garantie)

Pour rendre `fstats` visible, il faut une intégration CI simple.

Exemple GitHub Action :

```yaml
- name: Check text quality
  run: |
    fstats docs/**/*.md \
      --fail-if avg_sentence_words>25 \
      --fail-if max_line_length>120
```

Encore mieux : fournir une action officielle :

```yaml
- uses: yourorg/fstats-action@v1
  with:
    files: docs/**/*.md
    fail_if: avg_sentence_words>25
```

Pour GitLab CI :

```yaml
text-quality:
  script:
    - fstats docs/**/*.md --fail-if avg_line_length>120
```

C’est souvent comme ça qu’un petit outil devient indispensable.

---

# 11. Architecture Free Pascal (DREAM)

Pour garder le projet maintenable.

## Structure suggérée, espérée

```text
fstats/
  src/
    fstats.pas
    core/
      fstats_types.pas
      fstats_utf8.pas
      fstats_counter.pas
      fstats_wordmap.pas
      fstats_sentence.pas
      fstats_line.pas
    analyzers/
      fstats_basic_analyzer.pas
      fstats_lexical_analyzer.pas
      fstats_log_analyzer.pas
    output/
      fstats_console.pas
      fstats_json.pas
      fstats_csv.pas
      fstats_markdown.pas
    cli/
      fstats_args.pas
      fstats_config.pas
      fstats_checks.pas
  tests/
    golden/
    units/
    corpus/
  docs/
  packaging/
```

---

## Principes

1. **Ne pas charger tout le fichier en mémoire**
   - Lire par blocs.
   - Décodage UTF-8 incrémental.
   - Compteurs en streaming.

2. **Top-K borné**
   - Ne pas tout stocker si `--top 10`.
   - Mais si `--all`, attention mémoire sur gros corpus.
   - Ajouter `--max-unique=N`.

3. **Découpler analyse et sortie**
   - Un objet `TStatsResult` ou record structuré.
   - Writers console/JSON/CSV indépendants.

4. **Tests golden**
   - Fichiers de référence.
   - Sortie console stable.
   - JSON validé par parseur.
   - Tests de non-régression.

5. **Fuzzer UTF-8**
   - Générer séquences invalides.
   - Tester BOM, CR, LF, CRLF, NEL, contrôles.
   - Tester gros fichiers.

---

# 12. Idées de commandes futures

Voici à quoi pourrait ressembler une v3.

---

## Audit simple

```sh
fstats report.txt
```

## JSON propre

```sh
fstats report.txt --json --out report.json
```

## Multi-fichiers NDJSON

```sh
fstats logs/*.log --json-mode=ndjson --out logs.ndjson
```

## Corpus agrégé

```sh
fstats corpus/*.txt --aggregate --json --out corpus.json
```

## Check CI

```sh
fstats docs/*.md \
  --fail-if avg_line_length>120 \
  --fail-if non_utf8>0 \
  --fail-if words<100
```

## Comparaison baseline

```sh
fstats new.txt --compare baseline.json --fail-on-delta words>10%
```

## Logs

```sh
fstats app.log --pattern ERROR,WARN --json
```

## SCADA / alarmes

```sh
fstats alarms.log --mode=alarm --json
```

## Watch

```sh
fstats --watch app.log --interval 2
```

## N-grams

```sh
fstats corpus.txt --ngrams 2 --top-ngrams 50
```

## Redaction

```sh
fstats app.log --redact email,ipv4,url
```

---

# 13. Roadmap prévue (normalement)

## v2.2 — Robustesse et pipelines

Objectif : rendre l’outil vraiment utilisable en script.

À ajouter :

- stdin `-`
- `--files-from`
- glob interne
- `--recursive`
- NDJSON
- JSON multi-fichiers valide
- CSV v2 avec colonne `file`
- diagnostics UTF-8
- détection binaire
- `--quiet`, `--verbose`, `debug`
- exit codes enrichis
- `--summary-json`
- tests golden

Cette version n’est pas encore killer, mais elle devient sérieuse. Si

---

## v3.0 — Quality Gate

Objectif : transformer `fstats` en outil de contrôle.

À ajouter :

- `fstats check`
- seuils `--fail-if`
- baseline `--compare`
- `--fail-on-delta`
- config file TOML ou JSON
- rapports Markdown
- complétions shell
- GitHub Action / CI examples
- documentation use-case

Là, `fstats` devient vraiment différenciant.

---

## v3.5 — Corpus / Logs Intelligence

Objectif : devenir outil d’analyse avancée.

À ajouter :

- n-grams
- lexical stats
- entropy
- histograms
- readability
- patterns/regex
- log level detection
- alarm mode
- watch mode
- redaction
- SQLite export optionnel

---

# 14. Ce qu’il ne faut pas faire

Pour ne pas tuer le projet.

## 1. Ne pas faire une GUI lourde

Une interface graphique peut exister plus tard, mais le cœur doit rester CLI.

## 2. Ne pas faire un traitement de texte

Pas d’édition, pas de correction automatique.

## 3. Ne pas faire un NLP complet

Pas de modèle linguistique lourd, pas de dépendances massives.

## 4. Ne pas sacrifier la sortie ASCII

C’est un avantage énorme pour :

- redirection
- CI
- logs
- terminals industriels
- SCADA/IHM

## 5. Ne pas ajouter trop de formats exotiques trop tôt

JSON et CSV d’abord.
SQLite, Parquet, Grafana, MQTT plus tard ou PAS ! Sinon Fork ?

---

# 15. Les 3 features les plus rentables

Le meilleur pour moins d'effort, je ferais :

## 1. `stdin + multi-fichiers JSON/NDJSON propre`

Parce que sans ça, l’outil est moins intégrable.

## 2. `fstats check`

Parce que ça transforme l’outil en gate CI.

## 3. `fstats diff/compare`

Parce que ça transforme l’outil en outil de suivi et de QA.

---

# 16. Recommandation finale

Pour que `fstats` devienne une killer app, il ne faut pas seulement ajouter plus de statistiques.

Il faut lui donner un rôle clair :

> **Mesurer, comparer et contrôler du texte dans des pipelines.**

La meilleure version de `fstats` serait :

```text
fstats = wc + textstat + log profiler + CI gate + JSON exporter
```

mais en restant :

- rapide
- portable
- sans dépendance
- ASCII-friendly
- scriptable
- adapté Windows/Linux/Termux/ARM64

La phrase produit pourrait être :

> **fstats analyzes text files, logs and corpus; exports JSON/CSV; checks quality thresholds; and fails CI when text drifts.**

Si je devais choisir une niche principale, je vise :

1. **CI / text quality gate** pour docs/logs
2. puis **corpus profiling**
3. puis **SCADA/log sentinel** comme spécialisation avancée.
