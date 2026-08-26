# fstats — le guide pour comprendre et utiliser l'outil

> Ce guide s'adresse à tout le monde : aucune connaissance en programmation
> n'est nécessaire. Tu y apprendras ce que fait `fstats`, comment l'installer,
> et comment lire ses résultats. Les exemples montrent de **vraies sorties**
> de l'outil.

---

## 1. C'est quoi, fstats ?

`fstats` est un petit programme qui **analyse des fichiers texte** et te donne
des **chiffres sur leur contenu** :

- combien de **caractères**, de **mots**, de **lignes** et de **phrases** ;
- quels sont les **mots les plus fréquents** ;
- quelles **expressions reviennent** (groupes de mots qui se suivent) ;
- des informations de **qualité** : encodage cassé, fins de ligne Windows,
  tabulations…

Il est pensé pour être **simple, rapide et fiable** :

- **aucune dépendance** : un seul fichier exécutable ;
- **Windows et Linux** : les mêmes commandes partout ;
- **scriptable** : la sortie peut être du JSON ou du CSV, pas seulement du texte.

### Pour qui ?

- les **étudiants** qui analysent des textes (mémoire, corpus) ;
- les **développeurs** qui veulent des statistiques sur des logs ou des données ;
- les **curieux** qui veulent explorer un texte.

### Ce qu'il ne fait pas (pour être honnête)

- il n'analyse pas le **sens** des mots (pas d'IA, pas de sentiment) ;
- il lit des **fichiers texte UTF-8** (pas de fichiers binaires) ;
- il n'est pas conçu pour des fichiers de plusieurs gigaoctets (mais il
  documente ses limites et sait borner sa mémoire).

---

## 2. Installer fstats

Pour l'instant, fstats se **compile depuis les sources** (il n'y a pas encore
de binaires pré-construits à télécharger). Il te faut :

1. le compilateur **Free Pascal** (gratuit) — `fpc` en ligne de commande ;
2. les sources du projet :

```
git clone https://github.com/mickael-cala/fstats-cli.git
cd fstats-cli
```

3. compiler, depuis la racine du dépôt :

```
fpc -O2 -Mobjfpc -FE. src\fstats.pas
```

L'exécutable `fstats.exe` (Windows) ou `fstats` (Linux) apparaît à la racine.

> **Vérifie que tout fonctionne :**

```
fstats --version
```

Doit afficher quelque chose comme `fstats 2.6.1`.

> **Note Windows** : `wbld.bat` compile sans avoir à taper la commande,
> `wclr.bat` supprime les fichiers de compilation (`*.o`, `*.ppu`, `*.exe`).

---

## 3. Première analyse, étape par étape

Crée un petit fichier texte, par exemple `test.txt`, avec ce contenu
(3 lignes) :

```
Voici un exemple simple.
Deuxième phrase avec des mots.
Encore un test !
```

Puis lance :

```
fstats test.txt
```

Voici ce que fstats affiche (sortie réelle, sur ce même texte) :

```
File: test.txt
Generated: 2026-08-26 18:53:29

Summary
-------
  Lines:               3
  Words:              13
  Characters:         72
  Sentences:           3
  Avg words/sentence:  4
  Line length:  min 16, max 30, avg 23

Top Characters (10 of 25)
-------------------------
   #  Char      Code         Count
   1  'e'       U+0065          11
   2  ' '       U+0020          10
   ...

Top Words (10 of 12)
--------------------
   #  Word                 Count
   1  'un'                     2
   2  'des'                    1
   ...

Longest Lines
-------------
   #  Length  Preview
   1      30  Deuxième phrase avec des mots.
```

### Comment lire ce tableau

| Ligne | Ça veut dire quoi |
|---|---|
| `Lines: 3` | le fichier a 3 lignes |
| `Words: 13` | fstats a trouvé 13 mots |
| `Characters: 72` | 72 caractères au total (espaces et sauts de ligne compris) |
| `Sentences: 3` | 3 phrases (terminées par `.`, `!`, `?` ou `…`) |
| `Avg words/sentence: 4` | en moyenne, 4 mots par phrase |
| `Line length: min 16, max 30, avg 23` | la ligne la plus courte fait 16 caractères, la plus longue 30, moyenne 23 |
| `Top Characters` | les caractères les plus fréquents (ici `e` 11 fois, espace 10 fois…) |
| `Top Words` | les mots les plus fréquents (ici `un` 2 fois, tous les autres 1 fois) |
| `Longest Lines` | les 10 lignes les plus longues, avec un aperçu |

C'est tout : **une commande, et tu sais l'essentiel d'un texte.**

---

## 4. Les options utiles au quotidien

### Analyser plusieurs fichiers, des dossiers, ou l'entrée standard

| Commande | Effet |
|---|---|
| `fstats a.txt b.txt` | analyse les deux fichiers (un résumé par fichier) |
| `fstats "**/*.md"` | analyse **tous** les `.md` du dossier et sous-dossiers |
| `fstats "*.log"` | analyse tous les `.log` du dossier courant |
| `echo "un deux trois." \| fstats -` | analyse un texte passé « à la volée » (stdin) |
| `fstats --recursive=src --include='**/*.pas'` | parcourt l'arborescence `src` en filtrant |

> Les motifs `*.txt` / `**/*.md` sont gérés **par fstats lui-même** : pas besoin
> que ton terminal sache expandre les globs (utile sous Windows).

### Choisir la sortie

| Commande | Effet |
|---|---|
| `fstats --json fichier.txt` | sortie JSON (lisible par des programmes) |
| `fstats --summary-json fichier.txt` | une ligne JSON par fichier (parfait pour `jq`) |
| `fstats --csv fichier.txt` | tableau CSV (importable dans Excel) |
| `fstats --json --out=rapport.json fichier.txt` | écrit la sortie dans un fichier |

### Explorer le vocabulaire et les répétitions

| Commande | Effet |
|---|---|
| `fstats --lexical-stats fichier.txt` | mots uniques, hapax, entropie… |
| `fstats --ngrams=2 fichier.txt` | les paires de mots les plus fréquentes |
| `fstats --ngrams=3 --top-ngrams=10 fichier.txt` | les 10 triplets de mots les plus fréquents |
| `fstats --ngrams=2 --stopwords=fr fichier.txt` | bigrammes sans les mots vides (« le », « de »…) |
| `fstats --histogram=word_length fichier.txt` | répartition des longueurs de mots |
| `fstats --char-classes fichier.txt` | lettres / chiffres / blancs / ponctuation… |

> `fstats --help` liste toutes les options, et le
> [README](../README.md) donne la référence complète.

### Évaluer la lisibilité d'un texte

```
fstats --readability test.txt
```

```
Readability
-----------
  Avg sentence words:4.3333
  Avg word chars: 4.6154
  Pct long words:23.0769%
  Score (0-100): 76.6239
```

Quatre indicateurs, sans rien installer : combien de mots par phrase en
moyenne, combien de caractères par mot, la part de mots longs (7 caractères
ou plus), et un score de 0 à 100 (plus c'est haut, plus c'est facile à lire).
C'est une approximation **sans syllabes** — pas un Flesch-Kincaid exact — mais
suffisante pour comparer deux versions d'un texte entre elles.

### Vérifier la qualité automatiquement (pour la CI)

`fstats` peut jouer le rôle de **garde-fou** : des checks sur des seuils, avec
des codes de sortie que les scripts peuvent tester.

```
fstats --check --fail-if max_line_length>25 test.txt
```

```
Summary
-------
  Lines:               3
  Words:              13
  Characters:         72
  Sentences:           3
  Avg words/sentence:  4
  Line length:  min 16, max 30, avg 23

Checks
------
  max_line_length > 25 : FAIL (actual 30)
```

Ici, la plus longue ligne fait 30 caractères : le check `max_line_length > 25`
échoue et la commande se termine avec le code 2 (au lieu de 0). Codes de
sortie en mode check : **0** = tout va bien, **2** = au moins un check échoué,
**3** = seulement des avertissements (`--warn-if`), **1** = erreur (fichier
introuvable, option invalide).

Pour surveiller la **dérive** d'un corpus dans le temps, on capture un état de
référence puis on compare :

```
fstats --summary-json docs/*.md > baseline.ndjson
fstats docs/*.md --compare baseline.ndjson --fail-on-delta lines>10
```

Cette deuxième commande échoue (code 2) si un fichier gagne ou perd plus de
10 % de lignes par rapport à la baseline. C'est ce que la CI du dépôt fait
déjà sur ses propres documents (dogfood).

---

## 5. Comment fstats compte les choses

### Un « caractère »

fstats compte les **caractères Unicode** (appelés « code points »), dans un
fichier encodé en **UTF-8**. Les accents (`é`, `à`), les lettres accentuées et
même les caractères d'autres alphabets comptent pour un caractère chacun.
L'outil ne coupe jamais un caractère en deux, même si le fichier est mal formé.

### Un « mot » — et pourquoi ça dépend du mode

La définition d'un mot peut changer selon le mode choisi :

| Mode | Exemple avec `simple.` | Effet |
|---|---|---|
| `raw` (défaut) | le mot est `simple.` | la ponctuation collée au mot en fait partie |
| `ascii` | le mot est `simple` | lettres/chiffres ASCII seulement, ponctuation retirée |
| `unicode` | le mot est `simple` | lettres/chiffres Unicode (accents, grec, cyrillique…) |

Donc avec le mode par défaut, `fstats test.txt` compte `mots.` (avec le point)
comme un mot. Pour des mots « propres », utilise `--word-mode=ascii` ou
`--word-mode=unicode`.

### Une « phrase »

Une phrase se termine par `.`, `!`, `?` ou `…` (points de suspension). Si le
fichier se termine par du texte sans ponctuation finale, une dernière phrase
est comptée. Depuis la v2.6.1, un point **entre deux chiffres** (`3.14`) ne
clôture pas une phrase : c'est une décimale. En revanche `Version 3. Fin.`
clôture bien après le `3.` (le point est suivi d'un espace).

### Un « n-gramme »

Un n-gramme, c'est **n mots qui se suivent** :

- avec `--ngrams=2` : les **bigrammes** — pour « Le chat dort » → `le chat`, `chat dort` ;
- avec `--ngrams=3` : les **trigrammes** — `le chat dort`.

C'est pratique pour repérer les expressions qui reviennent dans un texte.
Les fenêtres ne traversent pas les sauts de ligne (chaque ligne produit ses
propres n-grammes).

### Les compteurs de qualité

fstats vérifie aussi la « santé » du fichier :

| Compteur | Détecte |
|---|---|
| `invalid_utf8` | un encodage cassé (remplacé par le caractère U+FFFD) |
| `bom` | un BOM UTF-8 en début de fichier (marqueur d'encodage) |
| `crlf` | les fins de ligne Windows `\r\n` |
| `tabs` | les tabulations |
| `nonprintable` | les caractères de contrôle |

Ces compteurs n'**affectent pas** les statistiques principales : ils les
complètent pour le diagnostic.

---

## 6. Exemples concrets (avec de vraies sorties)

Reprenons notre petit fichier `test.txt` (3 lignes, 13 mots).

### a) Résumé en une ligne JSON

```
fstats --summary-json test.txt
```

```
{"file": "test.txt", "tool": "fstats", "version": "2.6.1", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0}
```

Tout est sur **une ligne** : idéal pour traiter beaucoup de fichiers avec des
scripts.

### b) Depuis l'entrée standard

```
echo "un deux trois." | fstats - --summary-json
```

```
{"file": "stdin", "tool": "fstats", "version": "2.6.1", "schema_version": "1.0", "lines": 1, "words": 3, "characters": 16, "sentences": 1, "avg_words_per_sentence": 3, "line_min": 14, "line_max": 14, "line_avg": 14, "invalid_utf8": 0, "bom": false, "crlf": 1, "tabs": 0, "nonprintable": 0}
```

On peut enchaîner : `cat journal.log | fstats - --summary-json`.

### c) Les bigrammes les plus fréquents

```
fstats --ngrams=2 --word-mode=ascii test.txt
```

```
N-grams (N=2)
-------------
   #  N-gram                       Count
   1  avec des                         1
   2  des mots                         1
   3  deuxi me                         1
   ...
```

Chaque paire de mots consécutifs est comptée. Ici, toutes les paires
apparaissent une seule fois (petit texte). Sur un vrai corpus, les expressions
répétées remontent en tête.

> Petite curiosité visible ici : en mode `ascii`, « Deuxième » est découpé en
> `deuxi` + `me` (le `è` n'est pas ASCII). Avec `--word-mode=unicode`, le mot
> reste entier.

### d) Un histogramme

```
fstats --histogram=word_length --word-mode=ascii test.txt
```

```
Histogram (word_length)
-----------------------
  1-2    ### 3
  3-4    #### 4
  5-6    ##### 5
  7-8    # 1
  9-10    0
  11-12   0
  13+     0
```

Chaque `#` vaut une occurrence. On voit d'un coup d'œil que les mots font
surtout 1 à 6 caractères.

### e) Exporter pour Excel

```
fstats --csv test.txt
```

```
file,type,rank,value,code_point,count,length
test.txt,summary,,lines,,3,
test.txt,summary,,words,,13,
test.txt,summary,,characters,,72,
...
```

Un fichier par ligne, ouvrable dans n'importe quel tableur.

### f) La lisibilité d'un texte

```
fstats --readability test.txt
```

```
Readability
-----------
  Avg sentence words:4.3333
  Avg word chars: 4.6154
  Pct long words:23.0769%
  Score (0-100): 76.6239
```

- **Avg sentence words** : en moyenne, 4,3 mots par phrase — des phrases
  courtes, faciles à suivre.
- **Avg word chars** : 4,6 caractères par mot en moyenne (ponctuation
  comprise, mode par défaut).
- **Pct long words** : 23 % des mots font 7 caractères ou plus
  (`exemple`, `simple.`, `Deuxième`).
- **Score (0-100)** : 76,6 sur 100 — un texte plutôt facile à lire.

Le score est calculé sans syllabes (formule documentée dans la
[spécification technique](SEMANTIQUE.md)) : ce n'est pas un Flesch-Kincaid
exact, mais il permet de comparer deux versions d'un texte :

```
fstats --readability --summary-json test.txt
```

```
{"file": "test.txt", "tool": "fstats", "version": "2.6.1", "schema_version": "1.0", "lines": 3, "words": 13, "characters": 72, "sentences": 3, "avg_words_per_sentence": 4, "line_min": 16, "line_max": 30, "line_avg": 23, "invalid_utf8": 0, "bom": false, "crlf": 0, "tabs": 0, "nonprintable": 0, "avg_sentence_words": 4.333333, "avg_word_chars": 4.615385, "pct_long_words": 23.076923, "readability_score": 76.623932}
```

> Le mode `--word-mode=ascii` change les mots utilisés : « Deuxième » devient
> `deuxi` + `me` (le `è` n'est pas ASCII), donc `Avg word chars` et
> `Pct long words` changent aussi (4.3077 et 7.6923% sur ce fichier).

---

## 7. Les trois formats de sortie en un coup d'œil

| Format | Quand l'utiliser |
|---|---|
| **Console** (défaut) | lire les résultats à l'écran ; sections alignées, ASCII pur |
| **JSON** (`--json`, `--summary-json`) | traiter les résultats avec des scripts / outils |
| **CSV** (`--csv`) | importer dans un tableur, faire des graphiques |

Les détails techniques des schémas (champs exacts, modes `ndjson`/`array`/
`aggregate`, CSV `summary`/`words`/`chars`) sont dans la
[spécification technique](SEMANTIQUE.md).

---

## 8. Erreurs et codes de retour

| Code | Signification | Exemple |
|---|---|---|
| `0` | tout s'est bien passé | `fstats test.txt` |
| `1` | une erreur est survenue | fichier inexistant, option inconnue, glob sans résultat… |

Les erreurs sont écrites sur **stderr** avec un message explicite, la sortie
normale (les données) sur **stdout** : tu peux rediriger l'une sans l'autre.

---

## 9. Limites (dites honnêtement)

- **Fichiers texte UTF-8 uniquement** : pas de binaire, pas d'encodage latin-1.
  Un encodage cassé est détecté (`invalid_utf8`) et réparé avec U+FFFD.
- Le **BOM n'est pas retiré** : détecté (`bom`) mais conservé dans les données.
- En mode `raw` (défaut), la **ponctuation collée aux mots** en fait partie :
  pour des mots « propres », choisis `--word-mode=ascii|unicode`.
- Le repli de casse Unicode (`--casefold=unicode`) couvre les accents
  français/allemand courants, pas tout l'Unicode.
- Sur de **très gros** corpus, le top des n-grammes est approximatif (mémoire
  bornée) ; `--top-ngrams=0` lève la limite au prix de la mémoire.
- Un point **entre deux chiffres** (`3.14`) ne compte pas comme fin de phrase
  (v2.6.1) ; un point après un chiffre suivi d'un espace, si.

Dans 95 % des cas — fichiers normaux, textes de taille raisonnable — les
résultats sont exacts et fiables.

---

## 10. Pour aller plus loin

- [README](../README.md) — vue d'ensemble, toutes les options, exemples.
- [Spécification technique](SEMANTIQUE.md) — sémantique figée des compteurs,
  schémas JSON/CSV détaillés.
- [Journal de validation](VERIFICATION.md) — les vérifications effectuées
  avec leurs sorties réelles.
- [Roadmaps](ROADMAP-CIBLE2.md) / [ROADMAP-CIBLE3.md](ROADMAP-CIBLE3.md) —
  les fonctionnalités à venir.
- Les **tests automatisés** (`tests\run.bat` sous Windows, `tests\run.sh`
  sous Linux) vérifient que tout fonctionne après chaque modification.

Amuse-toi bien à explorer tes textes !
