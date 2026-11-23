{=============================================================================
  fstats_types.pas — constantes, variables globales et types partagés
  Unité de base du split de fstats.pas (v2.11.0). Aucune dépendance circulaire :
  toutes les autres unités (utf8, glob, lex, checks, analyzer, output) utilisent
  celle-ci. Le programme principal (fstats.pas) l'utilise aussi.
  =============================================================================}
unit fstats_types;

{$mode objfpc}
{$H+}

interface

uses
  SysUtils, Classes, Generics.Collections, Generics.Defaults;

const
  // Code page UTF-8 pour Windows - utilisé pour forcer l'encodage de la console
  CP_UTF8_LOCAL = 65001;
  
  // Taille du buffer de lecture fichier (64 Ko - bon compromis performance/mémoire)
  BUF_SIZE = 65536;
  
  // Nombre maximum d'éléments dans les "Top N" par défaut
  DEFAULT_TOP_LIMIT = 10;
  
  // Caractères de contrôle à échapper en JSON/CSV (pour éviter la corruption des formats)
  CTRL_CHARS = [#0..#31, #127];

  // Version du programme (affichée par --version et dans les exports JSON)
  FSTATS_VERSION = '2.14.0';

  // Borne mémoire par défaut sur le nombre de mots uniques stockés (--max-unique)
  DEFAULT_MAX_UNIQUE = 100000;

  // Seuil de « mot long » (--readability, C2-C) : longueur en code points à
  // partir de laquelle un token compte dans pct_long_words (>= 7).
  LONG_WORD_MIN_LEN = 7;

  // Delta de dérive « infini » (--fail-on-delta, Cible 1-C) : quand la base
  // de la baseline est 0 et que la valeur courante est > 0, le delta est
  // mathématiquement +Infini — le check échoue quel que soit le seuil.
  // 1e300 sert de représentation finie pour l'export JSON.
  INF_DELTA = 1e300;

  // Classes de caractères (--char-classes, C2-B) : l'ordre définit l'ordre
  // d'affichage/export (lettres, chiffres, blancs, ponctuation, contrôles, autres).
  CC_LETTERS = 0;
  CC_DIGITS = 1;
  CC_WHITESPACE = 2;
  CC_PUNCTUATION = 3;
  CC_CONTROL = 4;
  CC_OTHER = 5;
  CC_CLASS_COUNT = 6;

  // Cible 3-A : seuil de réduction du dictionnaire top-lines (comme les n-grams :
  // quand le dictionnaire dépasse max(8×K, 64) entrées, réduit au top-K).
  TOPLINES_PRUNE_THRESHOLD = 64;

var
  // Contrôle l'affichage des séquences ANSI (couleurs) : true = pas de couleurs.
  // Par défaut la sortie est en ASCII pur ; --color ne réactive les couleurs
  // que si la sortie standard est réellement une console (voir OutputIsConsole).
  NoColor: Boolean = True;

  // Mémoire de l'état de la sortie standard au démarrage (console vs pipe/fichier)
  StdOutIsConsole: Boolean = False;

  // Limites Top par section (--top-words=N / --top-chars=N, C2-A ; --top-ngrams=K,
  // C2-B). Déclarées ici (avant les fonctions d'export) car utilisées par
  // ExportCSV, ExportJSON et BuildJSONCompact ; 0 = tous (équivalent à --all).
  TopWordsLimit: Integer = DEFAULT_TOP_LIMIT;
  TopCharsLimit: Integer = DEFAULT_TOP_LIMIT;
  TopNgramsLimit: Integer = DEFAULT_TOP_LIMIT;
  // Cible 3-A : limite du top-lines identiques (--top-lines=N, défaut 10 ; 0 = désactivé)
  TopLinesDupLimit: Integer = DEFAULT_TOP_LIMIT;
  // Cible 3-C : limite du top des tags extraits (--top-tags=N, défaut 10)
  TopTagsLimit: Integer = DEFAULT_TOP_LIMIT;

  // Cible 3-D : mode watch — arrêt propre sur Ctrl+C (SIGINT/SIGTERM)
  WatchStop: Boolean = False;


type
  // Enregistrement pour stocker la fréquence d'un caractère (code point Unicode)
  TCharFreq = record
    CodePoint: UInt32;  // Code point Unicode (0..$10FFFF)
    Count: Int64;       // Nombre d'occurrences
  end;
  TCharFreqArray = array of TCharFreq;

  // Enregistrement pour stocker la fréquence d'un mot (texte)
  TWordFreq = record
    Word: string;       // Le mot tel qu'extrait (minuscule pour ASCII < 128)
    Count: Int64;       // Nombre d'occurrences
  end;
  TWordFreqArray = array of TWordFreq;

  // Tableau de chaînes (tokens d'une ligne, mots d'un n-gram, libellés de classes)
  TStringArray = array of string;

  // N-gram (incrément C2-B) : séquence de mots du mode courant + fréquence
  TNGramFreq = record
    Words: TStringArray;  // Mots (casefold appliqué, stopwords retirés)
    Count: Int64;         // Nombre d'occurrences
    Key: string;          // Clé interne (mots séparés par ' ') pour tri/égalité
  end;
  TNGramFreqArray = array of TNGramFreq;
  TNGramDict = specialize TDictionary<string, Int64>;

  // Langue des mots vides (--stopwords, C2-B) : listes courtes intégrées
  TStopWord = (swNone, swFR, swEN);

  // Type d'histogramme (--histogram, C2-B)
  THistogramKind = (hkNone, hkLineLength, hkWordLength, hkWordsPerSentence);

  // Options structure (C2-B) transmises à l'analyse : regroupées dans une
  // structure pour garder des signatures de procédures lisibles.
  TStructureOptions = record
    NGramSize: Integer;          // --ngrams=N (1..5, 0 = désactivé)
    TopNgramsLimit: Integer;     // --top-ngrams=K (0 = tous)
    StopWordMode: TStopWord;     // --stopwords=fr|en|none
    HistogramKind: THistogramKind; // --histogram=...
    CharClasses: Boolean;        // --char-classes
  end;

  // Enregistrement pour stocker une ligne et sa longueur
  TLineInfo = record
    Text: string;       // Contenu de la ligne (avec VisualChar appliqué)
    Len: Int64;         // Longueur en caractères (pas en octets)
  end;
  TLineArray = array of TLineInfo;

  // ============================================================================
  // CIBLE 3-A (Log Sentinel) — patterns, top-lignes, redaction
  // ============================================================================

  // Mode de redaction (--redact=email,ipv4,url) : appliquée aux SORTIES
  // uniquement (console/JSON/CSV), jamais aux compteurs calculés sur le brut.
  TRedactMode = (rmEmail, rmIPv4, rmURL);
  TRedactSet = set of TRedactMode;

  // Résultat d'un --pattern=TEXTE sur un fichier : nombre total d'occurrences
  // (matches) et nombre de lignes contenant au moins une occurrence (lines).
  TPatternMatch = record
    Pattern: string;    // Pattern tel que passé en ligne de commande
    Matches: Int64;     // Nombre total d'occurrences dans le fichier
    Lines: Int64;       // Nombre de lignes avec au moins un match
  end;
  TPatternMatchArray = array of TPatternMatch;

  // Ligne identique groupée (--top-lines=N) : texte brut + fréquence.
  TTopLine = record
    Line: string;       // Contenu brut de la ligne (redaction appliquée à l'affichage)
    Count: Int64;       // Nombre d'occurrences
  end;
  TTopLineArray = array of TTopLine;

  // ============================================================================
  // CIBLE 3-B (Log Sentinel) — niveaux de log et filtre
  // ============================================================================

  // Niveau de log détecté dans une ligne (mot entier, insensible à la casse,
  // priorité ERROR > WARN > INFO > DEBUG > TRACE ; llNone si aucun).
  TLogLevel = (llError, llWarn, llInfo, llDebug, llTrace, llNone);
  TLogLevelSet = set of TLogLevel;
  TLogLevelCount = array[TLogLevel] of Int64;

  // ============================================================================
  // CIBLE 3-C (Log Sentinel) — extraction de tags (mini-moteur regex subset)
  // ============================================================================

  // Token d'un pattern tag : littéral OU classe [..], avec quantifieur.
  // Quantifieurs supportés : (défaut)=1, '?'=0..1, '+'=1..inf, '*'=0..inf.
  TTagToken = record
    IsClass: Boolean;
    Ch: Char;                  // littéral (si IsClass=False)
    ClassSet: set of Char;     // classe (si IsClass=True)
    MinRep, MaxRep: Integer;   // bornes de répétition (MaxRep = MaxInt = infini)
  end;
  TTagPattern = array of TTagToken;

  // Tag extrait + fréquence (--regex-tag / --mode=alarm)
  TTagFreq = record
    Tag: string;
    Count: Int64;
  end;
  TTagFreqArray = array of TTagFreq;
  TTagDict = specialize TDictionary<string, Int64>;

  // Options Cible 3 transmises à l'analyse (comme TStructureOptions).
  TLogOptions = record
    Patterns: TStringArray;   // --pattern=... (répétable)
    TopLinesLimit: Integer;   // --top-lines=N (0 = désactivé)
    Redact: TRedactSet;       // --redact=email,ipv4,url
    LogLevels: Boolean;       // --log-level (détection des niveaux)
    FilterLevels: TLogLevelSet; // --filter=ERROR,WARN (filtre affichage lignes)
    RegexTag: string;         // --regex-tag=PATTERN ('' = désactivé)
    TopTagsLimit: Integer;    // --top-tags=N (borne du top des tags)
  end;

  // Dictionnaire pour le top-lines : ligne -> fréquence (borné comme les n-grams)
  TLineDict = specialize TDictionary<string, Int64>;

  // Structure principale contenant toutes les statistiques d'un fichier
  TStats = record
    Path: string;                    // Chemin du fichier analysé ('stdin' pour l'entrée standard)
    LineCount, WordCount, CharCount: Int64;  // Compteurs globaux
    SentenceCount: Int64;                    // Nombre de phrases (. ! ? …)
    AvgWordsPerSentence: Int64;              // WordCount div SentenceCount (0 si aucune)
    MinLen, MaxLen, AvgLen: Int64;           // Statistiques de longueur de ligne
    // Compteurs qualité (incrément A) — n'affectent pas les métriques existantes
    InvalidUTF8: Int64;              // Séquences UTF-8 invalides (remplacées par U+FFFD)
    BOM: Boolean;                    // True si U+FEFF est le tout premier caractère
    CRLF: Int64;                     // Nombre de fins de ligne CRLF
    Tabs: Int64;                     // Nombre de caractères TAB (U+0009)
    NonPrintable: Int64;             // Contrôles (U+0000..U+001F, U+007F) hors LF/CR/TAB
    Freq: TCharFreqArray;            // Tableau des fréquences de caractères
    Words: TWordFreqArray;           // Tableau des fréquences de mots
    UniqueWords: Int64;              // Types de mots stockés (plafonné --max-unique)
    WordCharsTotal: Int64;           // Somme des longueurs (code points) de tous les tokens
    LongWordCount: Int64;            // Tokens de >= 7 code points (--readability, C2-C)
    TopLines: TLineArray;            // Top N des lignes les plus longues
    // Structure (incrément C2-B) — sections ajoutées quand activées
    NGrams: TNGramFreqArray;         // Top-K n-grams (rempli si NGramSize > 0)
    NGramSize: Integer;              // N des n-grams (0 = désactivé)
    CharClasses: array[0..CC_CLASS_COUNT - 1] of Int64; // letters/digits/whitespace/punct/control/other
    CharClassesEnabled: Boolean;     // --char-classes actif (export des sections)
    HistogramKind: THistogramKind;   // hkNone = histogramme désactivé
    HistRanges: TStringArray;        // Libellés des classes (ex. '0-9','10-19',...)
    HistCounts: array of Int64;      // Comptes par classe (taille = nb de classes)
    // Cible 3-A (Log Sentinel) : patterns, top-lignes identiques, redaction
    PatternResults: TPatternMatchArray; // Résultats des --pattern (rempli si Patterns non vide)
    TopLinesDup: TTopLineArray;         // Top-K lignes identiques (--top-lines=N)
    TopLinesDupEnabled: Boolean;        // --top-lines actif
    Redact: TRedactSet;                 // --redact=email,ipv4,url (appliqué aux sorties seulement)
    // Cible 3-B : niveaux de log + filtre d'affichage
    LogLevelsEnabled: Boolean;          // --log-level actif
    LogLevels: TLogLevelCount;          // compteurs par niveau (somme = lines)
    FilterLevels: TLogLevelSet;         // --filter=... (filtre l'AFFICHAGE des lignes)
    // Cible 3-C : tags extraits (--regex-tag / --mode=alarm)
    TagsEnabled: Boolean;               // --regex-tag actif
    Tags: TTagFreqArray;                // top-K tags extraits (tri fréquence puis alpha)
  end;

  // Mode d'export JSON multi-fichiers (--json-mode)
  // jmAuto : 1 fichier = objet unique (rétrocompatible), plusieurs = NDJSON
  TJsonMode = (jmAuto, jmNDJSON, jmArray, jmAggregate);

  // Mode de tokenisation des mots (--word-mode, incrément C2-A)
  TWordMode = (wmRaw, wmAscii, wmUnicode);

  // Normalisation de casse des mots (--casefold, incrément C2-A)
  TCaseFold = (cfAscii, cfUnicode, cfNone);

  // Mode de comptage des phrases (--sentence-mode, v2.7.0)
  // smBasic : comportement historique exact (y compris la règle décimale
  //           v2.6.1 : 3.14 ne clôture pas) ;
  // smSmart : identique à basic, sauf pour le point '.' qui peut être
  //           avalé (abréviations, URLs) — sémantique figée dans le
  //           commentaire du bloc « Comptage des phrases » d'AnalyzeData.
  TSentenceMode = (smBasic, smSmart);

  // Sous-format d'export CSV v2 (--csv=summary|words|chars, C2-A)
  TCsvKind = (ckSummary, ckWords, ckChars);

  // Statistiques lexicales calculées à la volée (--lexical-stats, C2-A)
  TLexicalStats = record
    UniqueWords: Int64;          // Types de mots stockés (plafonné --max-unique)
    Hapax: Int64;                // Types à fréquence exactement 1
    TypeTokenRatio: Double;      // UniqueWords / WordCount (TTR)
    AverageWordLength: Double;   // Somme longueurs des tokens / WordCount
    EntropyBitsPerWord: Double;  // -Σ p_i log2 p_i sur les types du mode courant
  end;

  // Statistiques de lisibilité calculées à la volée (--readability, C2-C).
  // Inspirées de Flesch mais SANS syllabes (aucune détection de syllabes en
  // français) : moyenne de mots par phrase, longueur moyenne des mots, part
  // de mots longs (>= LONG_WORD_MIN_LEN) et score 0-100 (formule exacte
  // documentée dans ComputeReadability).
  TReadabilityStats = record
    AvgSentenceWords: Double;    // WordCount / SentenceCount (0 si aucune phrase)
    AvgWordChars: Double;        // WordCharsTotal / WordCount (0 si aucun mot)
    PctLongWords: Double;        // 100 * LongWordCount / WordCount (0 si aucun mot)
    Score: Double;               // Score 0-100 (formule documentée, 0 si aucun mot)
  end;

  // Opérateur de comparaison d'un check (grammaire figée du moteur, Cible 1-B)
  TCheckOp = (opGt, opGe, opLt, opLe, opEq, opNe);

  // Statut d'un check : ok | warn | fail (JSON en minuscules, console en
  // majuscules). Multi-fichiers : le pire statut gagne (fail > warn > ok).
  TCheckStatus = (csOk, csWarn, csFail);

  // Check défini sur la ligne de commande (--fail-if, --warn-if, --fail-on-delta)
  TCheck = record
    Metric: string;       // Nom canonique (ex. 'lines', 'non_utf8', 'invalid_utf8')
    Op: TCheckOp;         // Opérateur (toujours opGt pour les checks de dérive)
    Threshold: Double;    // Seuil (pour un delta : le seuil en %)
    IsWarn: Boolean;      // true = --warn-if (non bloquant), false = --fail-if
    IsDelta: Boolean;     // true = check de dérive (--fail-on-delta)
  end;
  TCheckArray = array of TCheck;

  // Résultat de l'évaluation d'un check sur un fichier (console + JSON)
  TCheckResult = record
    Id: string;           // 'lines', 'lines#2', 'delta:lines', 'delta:lines#2'...
    Metric: string;       // Nom canonique de la métrique
    Actual: Double;       // Valeur comparée (pour un delta : le delta en %)
    Op: TCheckOp;         // Opérateur
    Threshold: Double;    // Seuil (pour un delta : le seuil en %)
    Status: TCheckStatus; // ok | warn | fail
    IsDelta: Boolean;     // check de dérive (affichage 'delta <metric>')
    DeltaInf: Boolean;    // delta infini (base 0, actual > 0) : toujours fail
  end;
  TCheckResultArray = array of TCheckResult;

  // Entrée d'une baseline --summary-json (--compare, Cible 1-C) : chemin
  // "file" + paires clé/valeur de premier niveau (chaînes déséchappées).
  TBaselineEntry = record
    FilePath: string;     // Valeur "file" déséchappée (comparaison exacte)
    Keys: TStringArray;   // Clés JSON de premier niveau
    Values: TStringArray; // Valeurs brutes (déséchappées pour les chaînes)
  end;
  TBaselineArray = array of TBaselineEntry;

  // Dictionnaires hashés pour une insertion/recherche en O(1) - PERFORMANCE CRITIQUE
  // Sans cela, l'analyse de gros fichiers serait exponentiellement lente
  TCharDict = specialize TDictionary<UInt32, Int64>;
  TWordDict = specialize TDictionary<string, Int64>;
  
  // Types pour l'itération sur les paires clé/valeur des dictionnaires
  TCharPair = specialize TPair<UInt32, Int64>;
  TWordPair = specialize TPair<string, Int64>;

implementation

end.
