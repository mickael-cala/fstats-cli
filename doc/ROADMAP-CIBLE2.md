# Roadmap Cible 2 — Corpus Profiler

Statut : **C2-A, C2-B et C2-C livrés** (v2.5.0, tests OK, 2026-08-26).
Cible 2 complète.

Positionnement : `fstats` explore un corpus texte : vocabulaire, n-grammes,
distributions, export pour pandas/R/Excel.

Base : ROADMAPFULL.txt (Mode 2 « Corpus Profiler », §6.1-6.8, §8 CSV).
Dépend : Cible 1 livrée (v2.2.0 : glob, NDJSON/array/aggregate, --summary-json,
streaming, UTF-8 strict, compteurs qualité).

## Verdict

Prolongement naturel de la Cible 1 : elle réutilise les dictionnaires hashés
existants (`TCharDict`/`TWordDict`) et l'export JSON multi-fichiers déjà en
place. La valeur : faire de fstats un outil d'exploration de corpus
(docs, linguistique, NLP débutant) **sans aucune dépendance**, en restant
mono-fichier, streaming et ASCII-pur.

## État déjà en place (v2.2.0, vérifié)

- Streaming par blocs, dictionnaires O(1) caractères/mots
- Top 10 caractères/mots/lignes (`--all` pour tout)
- Multi-fichiers NDJSON/array/aggregate + `--summary-json`
- Globs/recursivité, stdin
- Compteurs qualité (diagnostic d'hygiène avant analyse lexicale)

## Roadmap FULL → adaptations (ce qui est possible)

| Feature (roadmap FULL) | Décision | Raison |
|---|---|---|
| Top words amélioré (`--word-mode`) | **FAIRE** (C2-A) | mécanisme simple sur le flux existant |
| Unicode case folding complet | **ADAPTER** : `ascii` d'abord, puis table basique d'accents | pas de case folding Unicode dans la RTL FPC ; périmètre documenté |
| Détection de phrases `smart` (décimales, abréviations, URLs) | **ADAPTER** : éviter les décimales seulement | heuristique complète hors de portée raisonnable, sémantique opaque |
| Statistiques lexicales (unique, hapax, TTR, entropie) | **FAIRE** (C2-A) | calcul trivial depuis les fréquences |
| N-grams | **FAIRE** (C2-B) | fenêtres bornées sur les mots |
| Histogrammes ASCII | **FAIRE** (C2-B) | réutilise la sortie console existante |
| Character classes | **FAIRE** (C2-B) | comptage pendant le décodage |
| Lisibilité (Flesch/Flesch-Kincaid…) | **ADAPTER** : métriques simples (mots/phrase, chars/mot, % mots longs, score 0-100 documenté) | syllabes non triviales en FR/EN, pas de lib |
| Export CSV v2 (colonne `file`, sous-formats) | **FAIRE** (C2-A) | utile pandas/Excel ; breaking documenté |
| SQLite / DuckDB / Parquet | **ÉCARTÉ** | roadmap §7.5 : « plus tard » |

## Incréments

### C2-A — Lexique (le cœur)

- `--word-mode=raw|ascii|unicode` : `raw` = comportement actuel ;
  `ascii` = mots `[A-Za-z0-9_]+` (ponctuation retirée) ; `unicode` = lettres et
  chiffres Unicode, ponctuation retirée.
- `--casefold=ascii|unicode|none` : `ascii` = minuscules ASCII (actuel) ;
  `unicode` = table basique limitée (accents français/allemand etc., périmètre
  documenté dans le README) ; `none` = casse conservée.
- `--lexical-stats` : `unique_words`, `hapax`, `type_token_ratio`,
  `average_word_length`, `entropy_bits_per_word` (approx. depuis les
  fréquences, formule documentée).
- `--top-words=N`, `--top-chars=N` (remplace la limite fixe 10), et
  `--max-unique=N` (garde mémoire, défaut 100 000).
- `--csv=summary|words|chars` : CSV v2 avec colonne `file`
  (en-tête `file,type,rank,value,code_point,count,length`).
- Sortie console : nouvelles sections, toujours ASCII pur.

### C2-B — Structure

- `--ngrams=N` (1..5) + `--top-ngrams=K` + `--stopwords=fr|en|none`
  (listes courtes intégrées).
- `--histogram=line_length|word_length|words_per_sentence` (classes ASCII
  identiques aux exemples de la roadmap).
- `--char-classes` : `letters`/`digits`/`whitespace`/`punctuation`/`control`/
  `other` (JSON + console).

### C2-C — Lisibilité (petite valeur ajoutée, optionnel) — LIVRÉ (v2.5.0)

- `--readability` : `avg_sentence_words`, `avg_word_chars`,
  `pct_long_words` (>= 7 caractères), score simple 0-100 (formule inspirée de
  Flesch, sans syllabes, documentée).
- Pas de Flesch-Kincaid exact : le dire dans le README.
- Livré : formule figée dans `doc/SEMANTIQUE.md` (« Sémantique de la
  lisibilité ») ; 6 nouveaux cas dans les deux suites (39 au total) ;
  `readability` en console, JSON pretty/NDJSON, `--summary-json` (clés
  plates), CSV summary ; non agrégé en `--json-mode=aggregate` (comme les
  n-grams).

## Sémantique à figer (dès C2-A)

- `word-mode=ascii` : mot = suite de `[A-Za-z0-9_]`, tout le reste sépare ;
  minuscules (sauf `casefold=none`).
- N-grams : fenêtres sur les mots du mode courant, ne traversent pas les sauts
  de ligne ; seuls les top-K sont conservés (mémoire bornée).
- `entropy = -Σ p_i log2 p_i` sur les types du mode courant.
- `hapax` = types à fréquence 1 ; `TTR` = types/tokens du mode courant.
- CSV v2 = **changement cassant** du format CSV actuel : le faire en C2-A,
  documenter, garder les valeurs strictement identiques.

## Garde-fous

- Pas de NLP lourd, pas de modèles, pas de dépendances : toujours un seul
  fichier Pascal, RTL FPC standard.
- Mémoire bornée : `--max-unique=N`, top-K bornés, n-grams limités aux top-K.
- Sortie console ASCII pure, pas d'ANSI en pipe.
- Ne pas changer la sémantique des compteurs existants en mode par défaut
  (régression interdite : test_fr.txt 3/13/72/3).

## Effort & risques

- Delta estimé : **~600-800 lignes** de Pascal (A ≈ 45 %, B ≈ 40 %, C ≈ 15 %).
- Risques : (1) CSV v2 cassant → documenter et le faire tôt ; (2) casefold
  unicode limité → périmètre explicite, pas de promesse « Unicode complet » ;
  (3) n-grams sur gros corpus → top-K bornés par défaut, `--max-unique`.
- Tests : fixtures corpus (fr/en, accents), golden, extension de
  `tests/run.bat`, validation JSON node.

## Décision

Ordre : **C2-A → C2-B → C2-C** (C2-C optionnel). Démarrer par C2-A.