{
  ============================================================================
  FSTATS - Analyseur de fichiers statistiques
  ============================================================================
  Auteur     : Expert Free Pascal
  Version    : 2.6.0 (Sécurisée)
  License    : MIT
  Compilation: fpc -O2 -Mobjfpc fstats.pas
  
  FONCTIONNALITÉS :
  - Analyse UTF-8 stricte de fichiers texte et de l'entrée standard (-/--stdin)
  - Statistiques : lignes, caractères, mots, phrases, longueurs de lignes
  - Compteurs qualité : UTF-8 invalide, BOM, CRLF, tabulations, contrôles
  - Glob interne (*, **, ?) et parcours récursif (--recursive/--include/--exclude)
  - Export JSON/CSV proprement échappé ; JSON multi-fichiers valide
    (NDJSON par défaut, --json-mode=array|aggregate), --summary-json plat
  - Sortie console compacte, alignée, ASCII pur (pipe/script friendly)
  - Structure (C2-B) : n-grams sur les mots du mode courant (--ngrams,
    --top-ngrams, --stopwords), histogrammes ASCII (--histogram), classes de
    caractères (--char-classes)
  - Lisibilité (C2-C) : --readability, 4 métriques + score 0-100 sans
    syllabes (inspiré de Flesch, documenté)
  - Checks / gate CI (Cible 1, B) : --check, --fail-if/--warn-if (10 métriques),
    exit codes 0/2/3/1 en mode check, section Checks console + JSON
  - Comparaison baseline (Cible 1, C) : --compare (NDJSON --summary-json) et
    --fail-on-delta METRIQUE>X pour détecter la dérive des métriques en %
  
  OPTIONS LIGNE DE COMMANDE :
  --char          : Afficher uniquement les stats de caractères
  --word          : Afficher uniquement les stats de mots
  --line          : Afficher uniquement les stats de lignes
  --all           : Exporter TOUTES les données (pas de limite Top 10)
  - , --stdin     : Analyser l'entrée standard (non mélangeable avec fichiers)
  --recursive=DIR : Parcourir récursivement un répertoire (répétable)
  --include=GLOB  : Filtre d'inclusion pour --recursive (répétable)
  --exclude=GLOB  : Filtre d'exclusion pour --recursive (répétable)
  --max-depth=N   : Profondeur maximale pour --recursive (0 = racine)
  --json          : Exporter en JSON (1 fichier : objet unique ;
                    plusieurs : NDJSON, un objet par ligne)
  --json-mode=M   : ndjson | array | aggregate (avec --json)
  --summary-json  : Objet JSON plat par fichier (scripts/jq)
  --csv           : Exporter en format CSV (stdout ou --out)
  --out=filename  : Rediriger la sortie vers un fichier
  --no-color      : Désactiver les couleurs ANSI (utile pour fichiers/logs)
  --color         : Forcer les couleurs même dans un fichier
  --quiet         : Supprimer l'affichage console quand --out est utilisé
  --check         : Mode check (gate CI) — implicite avec --fail-if/--warn-if/
                    --compare/--fail-on-delta ; exit 2 (fail) ou 3 (warn)
  --fail-if=SPEC  : Check bloquant : METRIQUE OPERATEUR SEUIL (répétable)
  --warn-if=SPEC  : Check non bloquant (même grammaire, répétable)
  --compare=F     : Baseline NDJSON (sortie --summary-json) pour --fail-on-delta
  --fail-on-delta=SPEC : Check de dérive METRIQUE>X (X en %, répétable)
  --help, -h      : Afficher l'aide et quitter
  --version       : Afficher la version et quitter
  
  SÉCURITÉ :
  - Validation stricte des chemins de fichiers (anti-path traversal)
  - Échappement rigoureux des caractères de contrôle en JSON/CSV
  - Gestion d'erreurs sans fuite d'informations sensibles
  - Protection contre les injections via les paramètres
  - Utilisation de try/finally pour la gestion mémoire
  
  COMPATIBILITÉ :
  - Windows (CP65001 UTF-8 forcé) et Linux/Mac (UTF-8 natif)
  - Free Pascal Compiler 3.2.2+ (mode objfpc)
  - Aucune console particulière requise (sortie ASCII par défaut)
  ============================================================================
}

program fstats;

{=============================================================================
  DIRECTIVES DE COMPILATION ET AVERTISSEMENTS
  =============================================================================}
{$WARN 3018 OFF}  // Constructing a class with abstract method (generic enumerators)
{$WARN 5024 OFF}  // Private type never used (internal generic types)
{$WARN 6058 OFF}  // Call to inline subroutine not inlined (generic methods)
{$mode objfpc}    // Mode de compilation compatible avec Delphi/Object Pascal
{$H+}             // Strings de type AnsiString avec gestion de longueur
{$codepage utf8}  // Source UTF-8 : les littéraux chaîne sont étiquetés UTF-8,
                  // pas CP1252 (sinon mojibake à l'écriture des messages)

{=============================================================================
  IMPORTS CONDITIONNELS SELON LA PLATEFORME
  =============================================================================}
{$IFDEF MSWINDOWS}
  // Windows : besoin de Windows API pour la gestion de la console UTF-8
  uses
    SysUtils, Classes, Windows, Generics.Collections, Generics.Defaults;
{$ELSE}
  // Linux/Mac : pas besoin d'API spécifique, UTF-8 natif
  uses
    SysUtils, Classes, Generics.Collections, Generics.Defaults;
{$ENDIF}

{=============================================================================
  CONSTANTES GLOBALES ET CONFIGURATION
  =============================================================================}
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
  FSTATS_VERSION = '2.6.0';

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

{=============================================================================
  VARIABLES GLOBALES DE CONTRÔLE D'AFFICHAGE
  =============================================================================}
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

{=============================================================================
  PROCÉDURE DE CONFIGURATION CONSOLE WINDOWS
  =============================================================================
  Objectif : Forcer la console Windows en UTF-8 et activer le support ANSI
  Sécurité : Ne modifie que la sortie standard, pas l'entrée
  Compatibilité : Fonctionne sur Windows 10+ avec Virtual Terminal Processing
  =============================================================================}
{$IFDEF MSWINDOWS}
procedure ConfigureConsoleForUTF8;
var
  hOut: THandle;
  dwMode: DWORD;
const
  // Flag pour activer le traitement des séquences d'échappement ANSI (couleurs)
  ENABLE_VIRTUAL_TERMINAL_PROCESSING = $0004;
begin
  // 1. Forcer l'encodage de sortie en UTF-8 (Code Page 65001)
  //    Cela garantit que WriteLn() envoie des octets UTF-8 valides
  SetConsoleOutputCP(CP_UTF8_LOCAL);
  SetConsoleCP(CP_UTF8_LOCAL);
  
  // 2. Activer le support des séquences ANSI pour les couleurs
  //    Sans cela, les codes #27'[0;32m' s'afficheraient en texte brut
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  if (hOut <> INVALID_HANDLE_VALUE) and GetConsoleMode(hOut, dwMode) then
    SetConsoleMode(hOut, dwMode or ENABLE_VIRTUAL_TERMINAL_PROCESSING);
end;
{$ENDIF}

{=============================================================================
  TYPES DE DONNÉES - STRUCTURES DE STOCKAGE
  =============================================================================}
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
  end;

  // Mode d'export JSON multi-fichiers (--json-mode)
  // jmAuto : 1 fichier = objet unique (rétrocompatible), plusieurs = NDJSON
  TJsonMode = (jmAuto, jmNDJSON, jmArray, jmAggregate);

  // Mode de tokenisation des mots (--word-mode, incrément C2-A)
  TWordMode = (wmRaw, wmAscii, wmUnicode);

  // Normalisation de casse des mots (--casefold, incrément C2-A)
  TCaseFold = (cfAscii, cfUnicode, cfNone);

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

{=============================================================================
  UTILITAIRES UTF-8 - GESTION SÉCURISÉE DES ENCODAGES
  =============================================================================
  Ces fonctions garantissent que :
  - On ne coupe jamais une séquence UTF-8 au milieu (évite les caractères corrompus)
  - On gère proprement les séquences invalides (remplacement par ?)
  - Les compteurs de longueur sont en caractères, pas en octets
  =============================================================================}

{-----------------------------------------------------------------------------
  UTF8SeqLen : Détermine la longueur d'une séquence UTF-8 à partir du premier octet
  Entrée  : B - Premier octet de la séquence
  Sortie  : Nombre d'octets attendus pour ce caractère (1 à 4) ou 1 si invalide
  Sécurité: Retourne 1 pour tout octet invalide pour éviter les boucles infinies
  -----------------------------------------------------------------------------}
function UTF8SeqLen(B: Byte): Integer;
begin
  if B < $80 then Exit(1);                    // ASCII simple (0xxxxxxx)
  if (B and $E0) = $C0 then Exit(2);          // Séquence 2 octets (110xxxxx)
  if (B and $F0) = $E0 then Exit(3);          // Séquence 3 octets (1110xxxx)
  if (B and $F8) = $F0 then Exit(4);          // Séquence 4 octets (11110xxx)
  Result := 1;                                // Octet invalide : traiter comme 1 octet
end;

{-----------------------------------------------------------------------------
  UTF8Length : Calcule le nombre de caractères Unicode dans une chaîne
  Entrée  : S - Chaîne UTF-8
  Sortie  : Nombre de caractères (pas d'octets)
  Usage   : Pour l'alignement visuel dans l'affichage console
  -----------------------------------------------------------------------------}
function UTF8Length(const S: string): Integer;
var
  i, L, Step: Integer;
begin
  Result := 0;
  i := 1;
  L := Length(S);
  while i <= L do
  begin
    Step := UTF8SeqLen(Byte(S[i]));
    Inc(i, Step);
    Inc(Result);
  end;
end;

{-----------------------------------------------------------------------------
  UTF8SafeCopy : Copie au plus MaxChars caractères d'une chaîne UTF-8
  Entrée  : S - Chaîne source, MaxChars - Nombre max de caractères à copier
  Sortie  : Sous-chaîne coupée à une frontière de caractère valide
  Sécurité: Ne coupe jamais au milieu d'une séquence UTF-8 multi-octets
  -----------------------------------------------------------------------------}
function UTF8SafeCopy(const S: string; MaxChars: Integer): string;
var
  i, L, Step, CharCount: Integer;
begin
  Result := '';
  i := 1;
  L := Length(S);
  CharCount := 0;
  while (i <= L) and (CharCount < MaxChars) do
  begin
    Step := UTF8SeqLen(Byte(S[i]));
    // Protection : si la séquence dépasse la fin de la chaîne, on arrête
    if i + Step - 1 > L then Break;
    Result := Result + Copy(S, i, Step);
    Inc(i, Step);
    Inc(CharCount);
  end;
end;

{-----------------------------------------------------------------------------
  UTF8PadRight : Ajoute des espaces à droite pour atteindre Width caractères
  Entrée  : S - Chaîne source, Width - Largeur cible en caractères (pas octets)
  Sortie  : Chaîne padding à droite avec des espaces
  Usage   : Alignement des colonnes dans l'affichage console
  -----------------------------------------------------------------------------}
function UTF8PadRight(const S: string; Width: Integer): string;
var
  N, i: Integer;
begin
  Result := S;
  N := UTF8Length(S);  // Compte les caractères, pas les octets
  for i := N + 1 to Width do
    Result := Result + ' ';
end;

{-----------------------------------------------------------------------------
  RepeatString : Répète une chaîne N fois
  -----------------------------------------------------------------------------
  Pourquoi : StringOfChar() exige un Char (1 octet). Les caractères Unicode
  de bordures (═, ─, │, etc.) font 3 octets en UTF-8 et sont donc des
  String, pas des Char. Cette fonction résout le problème pour toute
  chaîne multi-octets.
  -----------------------------------------------------------------------------}
function RepeatString(const S: string; Count: Integer): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Count do
    Result := Result + S;
end;

{=============================================================================
  ALGORITHMES DE TRI - QUICKSORT OPTIMISÉ
  =============================================================================
  Note : Ces tris sont stables et efficaces pour des tableaux de taille moyenne.
  Pour des datasets énormes (>1M éléments), envisager un tri externe ou radix.
  =============================================================================}

procedure QuickSortChars(var A: TCharFreqArray; L, R: Integer);
var
  I, J: Integer;
  P, T: TCharFreq;
begin
  I := L; J := R;
  P := A[(L + R) div 2];  // Pivot : élément médian pour équilibrer le tri
  repeat
    while A[I].Count > P.Count do Inc(I);  // Tri décroissant par fréquence
    while A[J].Count < P.Count do Dec(J);
    if I <= J then
    begin
      T := A[I]; A[I] := A[J]; A[J] := T;  // Échange
      Inc(I); Dec(J);
    end;
  until I > J;
  if L < J then QuickSortChars(A, L, J);
  if I < R then QuickSortChars(A, I, R);
end;

procedure QuickSortWords(var A: TWordFreqArray; L, R: Integer);
var
  I, J: Integer;
  P, T: TWordFreq;
begin
  I := L; J := R;
  P := A[(L + R) div 2];
  repeat
    while A[I].Count > P.Count do Inc(I);
    while A[J].Count < P.Count do Dec(J);
    if I <= J then
    begin
      T := A[I]; A[I] := A[J]; A[J] := T;
      Inc(I); Dec(J);
    end;
  until I > J;
  if L < J then QuickSortWords(A, L, J);
  if I < R then QuickSortWords(A, I, R);
end;

procedure QuickSortLines(var A: TLineArray; L, R: Integer);
var
  I, J: Integer;
  P, T: TLineInfo;
begin
  I := L; J := R;
  P := A[(L + R) div 2];
  repeat
    while A[I].Len > P.Len do Inc(I);  // Tri décroissant par longueur
    while A[J].Len < P.Len do Dec(J);
    if I <= J then
    begin
      T := A[I]; A[I] := A[J]; A[J] := T;
      Inc(I); Dec(J);
    end;
  until I > J;
  if L < J then QuickSortLines(A, L, J);
  if I < R then QuickSortLines(A, I, R);
end;

{=============================================================================
  GESTION DES COULEURS ANSI - AFFICHAGE CONSOLE
  =============================================================================
  Sécurité : Les couleurs sont désactivées PAR DÉFAUT. --color n'active un
  coloriage minimal des titres de section que si la sortie standard est
  réellement une console (jamais dans un pipe ni --out).
  =============================================================================}

{-----------------------------------------------------------------------------
  OutputIsConsole : Indique si la sortie standard est une console interactive
  Sortie  : True si stdout est une console
  Sécurité: GetConsoleMode échoue quand stdout est redirigé vers un fichier
            ou un pipe : les couleurs ne peuvent donc pas fuir dans un fichier
            ou un pipe, même avec --color.
  -----------------------------------------------------------------------------}
function OutputIsConsole: Boolean;
{$IFDEF MSWINDOWS}
var
  hOut: THandle;
  DwMode: DWORD;
begin
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  Result := (hOut <> INVALID_HANDLE_VALUE) and GetConsoleMode(hOut, DwMode);
end;
{$ELSE}
begin
  { Plateformes non-Windows : pas de test portable sans dépendance externe ;
    on considère la sortie comme une console. Le comportement ANSI reste quoi
    qu'il arrive contrôlé par NoColor (désactivé par défaut). }
  Result := True;
end;
{$ENDIF}

{-----------------------------------------------------------------------------
  AnsiColor : Génère une séquence ANSI pour changer la couleur du texte
  Entrée  : Code - Code couleur ANSI (30-37 pour couleurs de base)
  Sortie  : Chaîne d'échappement ANSI ou chaîne vide si NoColor=true
  -----------------------------------------------------------------------------}
function AnsiColor(const Code: Integer): string;
begin
  if NoColor then Exit('');  // Pas de couleurs si désactivé
  Result := #27'[0;' + IntToStr(Code) + 'm';  // ESC[0;CODEm
end;

{-----------------------------------------------------------------------------
  AnsiReset : Génère la séquence ANSI pour réinitialiser le style
  Sortie  : Chaîne d'échappement ANSI ou chaîne vide si NoColor=true
  -----------------------------------------------------------------------------}
function AnsiReset: string;
begin
  if NoColor then Exit('');
  Result := #27'[0m';  // ESC[0m - reset toutes les attributes
end;

{-----------------------------------------------------------------------------
  CurrentStamp : Horodatage de génération (traçabilité des sorties)
  Sortie  : "AAAA-MM-JJ HH:MM:SS" (heure locale, indépendant de la locale)
  -----------------------------------------------------------------------------}
function CurrentStamp: string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', Now);
end;

{=============================================================================
  VISUALISATION DES CARACTÈRES - AFFICHAGE SÉCURISÉ
  =============================================================================
  Objectif : Afficher les caractères de contrôle et Unicode de manière lisible
  Sécurité : Échappe les caractères qui pourraient casser l'affichage ou les exports
  =============================================================================}

{-----------------------------------------------------------------------------
  VisualChar : Convertit un code point Unicode en représentation visuelle sûre
  Entrée  : CP - Code point Unicode (0..$10FFFF)
  Sortie  : Représentation lisible :
            - Caractères de contrôle : \n, \t, \r, [CTRL], [NULL]
            - Espace : ' ' (visible)
            - ASCII imprimable : le caractère lui-même
            - Unicode : encodé en UTF-8 pour affichage
            - Caractère invalide : '?'
  Sécurité: Utilise la concaténation '\' + 'n' pour éviter que l'éditeur 
            ne transforme accidentellement en vrai caractère de contrôle
  -----------------------------------------------------------------------------}
{-----------------------------------------------------------------------------
  VisualChar — CORRECTION : conversion explicite Char -> string
-----------------------------------------------------------------------------}
function VisualChar(CP: UInt32): string;
var
  S: string;
begin
  if CP = $FFFD then begin Result := '?'; Exit; end;
  if CP = 0 then begin Result := '[NULL]'; Exit; end;

  if CP < 32 then
  begin
    case CP of
      9:  begin Result := '\t'; Exit; end;
      10: begin Result := '\n'; Exit; end;
      13: begin Result := '\r'; Exit; end;
      else begin Result := '[CTRL]'; Exit; end;
    end;
  end;

  if CP = 32 then begin Result := ' '; Exit; end;

  if CP < 128 then
  begin
    { CORRECTION : Chr() retourne Char, conversion explicite vers string }
    Result := String(Chr(CP));
    Exit;
  end;

  { Encodage UTF-8 pour CP >= 128 }
  S := '';
  if CP < $800 then
  begin
    S := S + Chr($C0 or (CP shr 6));
    S := S + Chr($80 or (CP and $3F));
  end
  else if CP < $10000 then
  begin
    S := S + Chr($E0 or (CP shr 12));
    S := S + Chr($80 or ((CP shr 6) and $3F));
    S := S + Chr($80 or (CP and $3F));
  end
  else
  begin
    S := S + Chr($F0 or (CP shr 18));
    S := S + Chr($80 or ((CP shr 12) and $3F));
    S := S + Chr($80 or ((CP shr 6) and $3F));
    S := S + Chr($80 or (CP and $3F));
  end;
  Result := S;
end;

{-----------------------------------------------------------------------------
  UnicodeCode : Formate un code point en notation Unicode standard U+XXXX
  Entrée  : CP - Code point Unicode
  Sortie  : Chaîne formatée "U+XXXX" (4 chiffres hexadécimaux minimum)
  Usage   : Affichage dans les statistiques pour référence technique
  -----------------------------------------------------------------------------}
function UnicodeCode(CP: UInt32): string;
begin
  Result := 'U+' + HexStr(CP, 4);  // HexStr avec padding à 4 chiffres
end;

{=============================================================================
  DÉCODEUR UTF-8 STRICT - VALIDATION DES DONNÉES D'ENTRÉE
  =============================================================================
  Objectif : Décoder une séquence UTF-8 en code point Unicode avec validation
  Sécurité : Rejette les séquences mal formées, sur-encodées, ou hors plage
  Retourne : True si décodage réussi, False sinon (avec CP=$FFFD, Used=1)
  =============================================================================}
function DecodeUTF8(const Buf: PByte; Len: Integer; out CP: UInt32; out Used: Integer): Boolean;
var
  B0, B1, B2, B3: Byte;
begin
  Result := False;
  Used := 1;  // Par défaut, on consomme 1 octet (même en cas d'erreur)
  
  if Len = 0 then Exit;  // Buffer vide
  
  B0 := Buf^;  // Premier octet
  
  // Cas 1 : ASCII simple (0xxxxxxx)
  if B0 < $80 then
  begin
    CP := B0;
    Exit(True);
  end;
  
  // Cas 2 : Séquence 2 octets (110xxxxx 10xxxxxx)
  if (B0 and $E0) = $C0 then
  begin
    if Len < 2 then Exit;  // Buffer trop court
    B1 := Buf[1];
    if (B1 and $C0) <> $80 then Exit;  // Second octet invalide
    CP := ((B0 and $1F) shl 6) or (B1 and $3F);
    // Validation : pas de sur-encodage (CP doit être >= $80)
    if CP < $80 then Exit;
    Used := 2;
    Exit(True);
  end;
  
  // Cas 3 : Séquence 3 octets (1110xxxx 10xxxxxx 10xxxxxx)
  if (B0 and $F0) = $E0 then
  begin
    if Len < 3 then Exit;
    B1 := Buf[1];
    B2 := Buf[2];
    if ((B1 and $C0) <> $80) or ((B2 and $C0) <> $80) then Exit;
    CP := ((B0 and $0F) shl 12) or ((B1 and $3F) shl 6) or (B2 and $3F);
    // Validation : pas de sur-encodage, pas de plages réservées
    if (CP < $800) or ((CP >= $D800) and (CP <= $DFFF)) then Exit;
    Used := 3;
    Exit(True);
  end;
  
  // Cas 4 : Séquence 4 octets (11110xxx 10xxxxxx 10xxxxxx 10xxxxxx)
  if (B0 and $F8) = $F0 then
  begin
    if Len < 4 then Exit;
    B1 := Buf[1];
    B2 := Buf[2];
    B3 := Buf[3];
    if ((B1 and $C0) <> $80) or ((B2 and $C0) <> $80) or ((B3 and $C0) <> $80) then Exit;
    CP := ((B0 and $07) shl 18) or ((B1 and $3F) shl 12) or ((B2 and $3F) shl 6) or (B3 and $3F);
    // Validation : plage Unicode valide (U+10000..U+10FFFF)
    if (CP < $10000) or (CP > $10FFFF) then Exit;
    Used := 4;
    Exit(True);
  end;
  
  // Séquence invalide : on retourne False, Used=1 pour avancer d'un octet
end;

{=============================================================================
  GESTION DES LIGNES - TOP N OU TOUTES
  =============================================================================
  Objectif : Maintenir une liste des N lignes les plus longues (ou toutes)
  Performance : Insertion triée en O(N) pour N petit (10), O(1) si --all
  =============================================================================}

{-----------------------------------------------------------------------------
  AddLine : Ajoute une ligne à la liste TopLines avec gestion de limite
  Entrée  : Arr - Tableau de lignes, S - Texte, Len - Longueur, MaxLines - Limite
  Comportement :
    - Si MaxLines <= 0 : mode --all, on ajoute tout (tri à la fin)
    - Sinon : mode Top N, on maintient seulement les N plus longues
  Sécurité : Vérifie que Len > 0 avant d'ajouter (pas de lignes vides)
  -----------------------------------------------------------------------------}
procedure AddLine(var Arr: TLineArray; const S: string; Len: Int64; MaxLines: Integer);
var
  i, j: Integer;
begin
  if Len = 0 then Exit;  // Ignore les lignes vides
  
  // Mode --all : accumulation simple, tri différé
  if MaxLines <= 0 then
  begin
    SetLength(Arr, Length(Arr) + 1);
    Arr[High(Arr)].Text := S;
    Arr[High(Arr)].Len := Len;
    Exit;
  end;

  // Mode Top N : insertion triée avec écrasement du dernier si nécessaire
  // Optimisation : si la nouvelle ligne est plus courte que la dernière du top, on ignore
  if (Length(Arr) = MaxLines) and (Len <= Arr[MaxLines - 1].Len) then Exit;

  // Trouver la position d'insertion (tri décroissant)
  i := 0;
  while (i < Length(Arr)) and (Arr[i].Len >= Len) do Inc(i);

  // Insérer à la position i
  if Length(Arr) = MaxLines then
  begin
    // Décaler les éléments vers la droite pour faire de la place
    for j := MaxLines - 2 downto i do Arr[j+1] := Arr[j];
    Arr[i].Text := S;
    Arr[i].Len := Len;
  end
  else
  begin
    // Tableau pas encore plein : étendre puis décaler
    SetLength(Arr, Length(Arr) + 1);
    for j := High(Arr) downto i+1 do Arr[j] := Arr[j-1];
    Arr[i].Text := S;
    Arr[i].Len := Len;
  end;
end;

{=============================================================================
  MOTEUR DE GLOB INTERNE - RÉSOLUTION DES PATTERNS (incrément A)
  =============================================================================
  Objectif : Résoudre les patterns glob passés en arguments (les shells
  Windows - CMD/PowerShell - n'expandent PAS les globs, contrairement à
  bash/zsh) et filtrer les parcours --recursive.
  Sémantique :
    - '*'  : zéro ou plusieurs caractères, SANS traverser le séparateur de
             chemin ('/').
    - '**' : zéro ou plusieurs caractères, EN TRAVERSANT les séparateurs ;
             '**/' consomme en outre zéro ou plusieurs répertoires entiers.
    - '?'  : exactement un caractère, sans traverser le séparateur.
  La casse est insensible sur Windows (le système de fichiers l'est) et
  sensible sur les autres plateformes.
  Implémentation : récursive, sans bibliothèque externe.
  =============================================================================}

{-----------------------------------------------------------------------------
  IsPathSeparator : Vrai si C est un séparateur de chemin.
  Les chemins sont normalisés en '/' en interne sur Windows ; '/' est le
  seul séparateur possible sur les autres plateformes (le '\' y est un
  caractère de nom de fichier ordinaire).
  -----------------------------------------------------------------------------}
function IsPathSeparator(C: Char): Boolean;
begin
  Result := C = '/';
  {$IFDEF MSWINDOWS}
  if C = '\' then Result := True;
  {$ENDIF}
end;

{-----------------------------------------------------------------------------
  CharEquals : Comparaison de deux caractères pour le matching glob.
  Windows : insensible à la casse (UpCase ASCII ; le repli de casse complet
  de l'Unicode hors ASCII n'est pas appliqué - limite documentée).
  Autres plateformes : sensible à la casse.
  -----------------------------------------------------------------------------}
function CharEquals(A, B: Char): Boolean;
begin
  {$IFDEF MSWINDOWS}
  Result := UpCase(A) = UpCase(B);
  {$ELSE}
  Result := A = B;
  {$ENDIF}
end;

{-----------------------------------------------------------------------------
  GlobMatch : Vrai si le texte S correspond au pattern glob P.
  P peut contenir '*', '**' et '?'. Algorithme récursif à deux indices :
  chaque '*' explore toutes les positions de coupure possibles.
  -----------------------------------------------------------------------------}
function GlobMatch(const P, S: string): Boolean;

  function DoMatch(pi, si: Integer): Boolean;
  var
    pc: Char;
  begin
    while pi <= Length(P) do
    begin
      pc := P[pi];
      if pc = '*' then
      begin
        // '**' : deux étoiles consécutives
        if (pi < Length(P)) and (P[pi + 1] = '*') then
        begin
          Inc(pi, 2);
          // '**/' : zéro ou plusieurs répertoires entiers
          if (pi <= Length(P)) and (P[pi] = '/') then
          begin
            Inc(pi);
            if DoMatch(pi, si) then Exit(True);   // zéro répertoire
            while si <= Length(S) do
            begin
              if IsPathSeparator(S[si]) then
              begin
                Inc(si);
                if DoMatch(pi, si) then Exit(True);
              end
              else
                Inc(si);
            end;
            Exit(False);
          end;
          // '**' seul : zéro ou plusieurs caractères, séparateurs compris
          while si <= Length(S) do
          begin
            if DoMatch(pi, si) then Exit(True);
            Inc(si);
          end;
          Exit(DoMatch(pi, si));
        end;
        // '*' : zéro ou plusieurs caractères hors séparateur
        if DoMatch(pi + 1, si) then Exit(True);
        while (si <= Length(S)) and (not IsPathSeparator(S[si])) do
        begin
          Inc(si);
          if DoMatch(pi + 1, si) then Exit(True);
        end;
        Exit(False);
      end;

      if si > Length(S) then Exit(False);
      if pc = '?' then
      begin
        if IsPathSeparator(S[si]) then Exit(False);
        Inc(pi); Inc(si);
      end
      else
      begin
        if not CharEquals(pc, S[si]) then Exit(False);
        Inc(pi); Inc(si);
      end;
    end;
    Result := si > Length(S);
  end;

begin
  Result := DoMatch(1, 1);
end;

{-----------------------------------------------------------------------------
  ContainsWildcard : Vrai si la chaîne contient '*' ou '?'.
  Usage : distinguer un pattern glob d'un chemin de fichier littéral.
  -----------------------------------------------------------------------------}
function ContainsWildcard(const S: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(S) do
    if (S[i] = '*') or (S[i] = '?') then Exit(True);
  Result := False;
end;

{-----------------------------------------------------------------------------
  ContainsDoubleStar : Vrai si la chaîne contient '**' consécutif.
  -----------------------------------------------------------------------------}
function ContainsDoubleStar(const S: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(S) - 1 do
    if (S[i] = '*') and (S[i + 1] = '*') then Exit(True);
  Result := False;
end;

{-----------------------------------------------------------------------------
  NormalizePath : Normalise un chemin pour le matching.
  Sur Windows, '\' devient '/' (les deux sont acceptés par l'API). Sur les
  autres plateformes, le chemin est renvoyé tel quel.
  -----------------------------------------------------------------------------}
function NormalizePath(const S: string): string;
{$IFDEF MSWINDOWS}
var
  i: Integer;
{$ENDIF}
begin
  Result := S;
  {$IFDEF MSWINDOWS}
  for i := 1 to Length(Result) do
    if Result[i] = '\' then Result[i] := '/';
  {$ENDIF}
end;

{-----------------------------------------------------------------------------
  JoinPath : Concatène deux éléments de chemin avec un '/' intercalaire.
  -----------------------------------------------------------------------------}
function JoinPath(const A, B: string): string;
begin
  if A = '' then
    Result := B
  else if A[Length(A)] = '/' then
    Result := A + B
  else
    Result := A + '/' + B;
end;

{-----------------------------------------------------------------------------
  ExtractBaseDir : Extrait le préfixe sans joker d'un pattern glob.
  Sortie  : le répertoire de départ du parcours (avec '/' final, ou '' si le
            pattern est relatif au répertoire courant).
  Exemple : 'docs/**/*.md' -> 'docs/' ; '*.txt' -> '' ; '**/*.log' -> ''.
  -----------------------------------------------------------------------------}
function ExtractBaseDir(const Pattern: string): string;
var
  i, LastSlash: Integer;
begin
  LastSlash := 0;
  for i := 1 to Length(Pattern) do
  begin
    if (Pattern[i] = '*') or (Pattern[i] = '?') then Break;
    if Pattern[i] = '/' then LastSlash := i;
  end;
  Result := Copy(Pattern, 1, LastSlash);
end;

{-----------------------------------------------------------------------------
  WalkAndMatch : Parcourt un répertoire (récursivement si Recurse) et ajoute
  à Results tous les fichiers dont le chemin (relatif au CWD) correspond au
  pattern glob. MatchCount reçoit le nombre de correspondances.
  -----------------------------------------------------------------------------}
procedure WalkAndMatch(const Dir: string; Recurse: Boolean; const Pattern: string;
                       const Results: TStringList; var MatchCount: Integer);
var
  Sr: TSearchRec;
  Full: string;
begin
  if FindFirst(JoinPath(Dir, '*'), faAnyFile, Sr) = 0 then
  begin
    repeat
      if (Sr.Name = '.') or (Sr.Name = '..') then Continue;
      Full := JoinPath(Dir, Sr.Name);
      if (Sr.Attr and faDirectory) <> 0 then
      begin
        if Recurse then
          WalkAndMatch(Full, True, Pattern, Results, MatchCount);
      end
      else if GlobMatch(Pattern, Full) then
      begin
        Results.Add(Full);
        Inc(MatchCount);
      end;
    until FindNext(Sr) <> 0;
    SysUtils.FindClose(Sr);
  end;
end;

{-----------------------------------------------------------------------------
  ResolveGlobPattern : Résout un pattern glob positionnel en liste de fichiers.
  Erreur fatale (exit 1) si le pattern ne correspond à AUCUN fichier :
  éviter qu'un gate CI soit silencieusement vide.
  -----------------------------------------------------------------------------}
procedure ResolveGlobPattern(const Pattern: string; const Results: TStringList);
var
  NormPattern, BaseDir: string;
  Recurse: Boolean;
  MatchCount: Integer;
begin
  NormPattern := NormalizePath(Pattern);
  Recurse := ContainsDoubleStar(NormPattern);
  BaseDir := ExtractBaseDir(NormPattern);
  MatchCount := 0;
  WalkAndMatch(BaseDir, Recurse, NormPattern, Results, MatchCount);
  if MatchCount = 0 then
  begin
    WriteLn(ErrOutput, 'Erreur: aucun fichier ne correspond au motif glob - ', Pattern);
    Halt(1);
  end;
end;

{-----------------------------------------------------------------------------
  CollectRecursive : Parcourt récursivement Root (--recursive=DIR) en
  appliquant les filtres d'inclusion/exclusion et la profondeur maximale.
  Les patterns Include/Exclude sont matchés contre le chemin relatif à la
  racine (séparateurs '/').
  -----------------------------------------------------------------------------}
procedure CollectRecursive(const Root: string; const IncludeP, ExcludeP: TStringList;
                           MaxDepth: Integer; const Results: TStringList);
var
  Found: Integer;

  procedure Walk(const CurDir, RelDir: string; Depth: Integer);
  var
    Sr: TSearchRec;
    Name, Full, Rel: string;
    k: Integer;
    Keep: Boolean;
  begin
    if FindFirst(JoinPath(CurDir, '*'), faAnyFile, Sr) = 0 then
    begin
      repeat
        Name := Sr.Name;
        if (Name = '.') or (Name = '..') then Continue;
        Full := JoinPath(CurDir, Name);
        if (Sr.Attr and faDirectory) <> 0 then
        begin
          if (MaxDepth < 0) or (Depth < MaxDepth) then
            Walk(Full, JoinPath(RelDir, Name), Depth + 1);
        end
        else
        begin
          Rel := JoinPath(RelDir, Name);
          Keep := IncludeP.Count = 0;
          for k := 0 to IncludeP.Count - 1 do
            if GlobMatch(IncludeP[k], Rel) then
            begin
              Keep := True;
              Break;
            end;
          if Keep then
            for k := 0 to ExcludeP.Count - 1 do
              if GlobMatch(ExcludeP[k], Rel) then
              begin
                Keep := False;
                Break;
              end;
          if Keep then
          begin
            Results.Add(Full);
            Inc(Found);
          end;
        end;
      until FindNext(Sr) <> 0;
      SysUtils.FindClose(Sr);
    end;
  end;

begin
  Found := 0;
  Walk(Root, '', 0);
  if Found = 0 then
  begin
    WriteLn(ErrOutput, 'Erreur: aucun fichier trouvé dans - ', Root);
    Halt(1);
  end;
end;

{-----------------------------------------------------------------------------
  QuickSortStrList : Tri lexical déterministe (CompareStr, comparaison
  d'octets) d'une TStringList - sorties reproductibles en CI, indépendantes
  de la locale du système.
  -----------------------------------------------------------------------------}
procedure QuickSortStrList(L: TStringList; Lo, Hi: Integer);
var
  I, J: Integer;
  P: string;
begin
  I := Lo; J := Hi;
  P := L.Strings[(Lo + Hi) div 2];
  repeat
    while CompareStr(L.Strings[I], P) < 0 do Inc(I);
    while CompareStr(L.Strings[J], P) > 0 do Dec(J);
    if I <= J then
    begin
      L.Exchange(I, J);
      Inc(I); Dec(J);
    end;
  until I > J;
  if Lo < J then QuickSortStrList(L, Lo, J);
  if I < Hi then QuickSortStrList(L, I, Hi);
end;

{-----------------------------------------------------------------------------
  DedupeSorted : Supprime les doublons d'une liste triée (mêmes globs ou
  fichiers passés plusieurs fois ne doivent pas doubler les totaux).
  -----------------------------------------------------------------------------}
procedure DedupeSorted(L: TStringList);
var
  Tmp: TStringList;
  i: Integer;
begin
  Tmp := TStringList.Create;
  try
    for i := 0 to L.Count - 1 do
      if (Tmp.Count = 0) or (CompareStr(L[i], Tmp[Tmp.Count - 1]) <> 0) then
        Tmp.Add(L[i]);
    L.Assign(Tmp);
  finally
    Tmp.Free;
  end;
end;

{=============================================================================
  TOKENISATION LEXICALE (incrément C2-A) — modes de mots et repli de casse
  =============================================================================
  --word-mode=raw    : comportement historique (mot = code point > 0x20,
                       ponctuation incluse, espaces/contrôles = séparateurs)
  --word-mode=ascii  : mot = suite de [A-Za-z0-9_], tout le reste sépare
  --word-mode=unicode: mot = suite de lettres/chiffres Unicode (périmètre
                       ci-dessous), ponctuation sépare
  --casefold=ascii   : minuscules ASCII (comportement historique)
  --casefold=unicode : minuscules ASCII + table basique d'accents
                       (français/allemand : Latin-1 accentués, Œ→œ, Ÿ→ÿ, ẞ→ß)
  --casefold=none    : casse conservée
  Le périmètre exact est documenté dans le README (« Sémantique lexicale »).
  =============================================================================}

{-----------------------------------------------------------------------------
  IsAsciiWordChar : Vrai si CP est un caractère de mot du mode ascii.
  Définition figée : [A-Za-z0-9_].
  -----------------------------------------------------------------------------}
function IsAsciiWordChar(CP: UInt32): Boolean;
begin
  Result := ((CP >= $30) and (CP <= $39)) or   // 0-9
            ((CP >= $41) and (CP <= $5A)) or   // A-Z
            ((CP >= $61) and (CP <= $7A)) or   // a-z
            (CP = $5F);                        // _
end;

{-----------------------------------------------------------------------------
  IsUnicodeWordChar : Vrai si CP est une lettre ou un chiffre Unicode du
  périmètre documenté : chiffres ASCII, lettres ASCII, Latin-1 (hors × ÷),
  Latin étendu A/B, API (alphabet phonétique), marques combinantes (restent
  attachées à la lettre), grec (hors point-virgule grec), cyrillique, latin
  étendu additionnel, chiffres arabo-indiens/étendus. Tout le reste
  (ponctuation, symboles, blancs) sépare les mots.
  -----------------------------------------------------------------------------}
function IsUnicodeWordChar(CP: UInt32): Boolean;
begin
  Result := False;
  if (CP >= $30) and (CP <= $39) then Exit(True);     // 0-9
  if (CP >= $41) and (CP <= $5A) then Exit(True);     // A-Z
  if (CP >= $61) and (CP <= $7A) then Exit(True);     // a-z
  if (CP >= $C0) and (CP <= $D6) then Exit(True);     // Latin-1 (hors ×)
  if (CP >= $D8) and (CP <= $F6) then Exit(True);     // Latin-1 (hors ÷)
  if (CP >= $F8) and (CP <= $24F) then Exit(True);    // Latin étendu A/B
  if (CP >= $250) and (CP <= $2AF) then Exit(True);   // API
  if (CP >= $300) and (CP <= $36F) then Exit(True);   // Marques combinantes
  if (CP >= $370) and (CP <= $3FF) and (CP <> $37E) then Exit(True); // Grec
  if (CP >= $400) and (CP <= $4FF) then Exit(True);   // Cyrillique
  if (CP >= $1E00) and (CP <= $1EFF) then Exit(True); // Latin étendu additionnel
  if (CP >= $660) and (CP <= $669) then Exit(True);   // Chiffres arabo-indiens
  if (CP >= $6F0) and (CP <= $6F9) then Exit(True);   // Chiffres arabes étendus
end;

{-----------------------------------------------------------------------------
  FoldChar : Repli de casse d'un code point selon --casefold.
  cfAscii   : A-Z -> a-z uniquement (comportement historique).
  cfUnicode : cfAscii + Latin-1 accentués (À..Þ -> à..þ, +$20), Œ->œ, Ÿ->ÿ,
              ẞ->ß. Table limitée : pas de folding Unicode complet (RTL FPC).
  cfNone    : identité (casse conservée).
  -----------------------------------------------------------------------------}
function FoldChar(CP: UInt32; CaseFold: TCaseFold): UInt32;
begin
  Result := CP;
  case CaseFold of
    cfNone: ;
    cfAscii:
      if (CP >= $41) and (CP <= $5A) then Result := CP + $20;
    cfUnicode:
      begin
        if (CP >= $41) and (CP <= $5A) then
          Result := CP + $20
        else if (CP >= $C0) and (CP <= $D6) then
          Result := CP + $20
        else if (CP >= $D8) and (CP <= $DE) then
          Result := CP + $20
        else if CP = $152 then
          Result := $153         // Œ -> œ
        else if CP = $178 then
          Result := $FF          // Ÿ -> ÿ
        else if CP = $1E9E then
          Result := $DF;         // ẞ -> ß
      end;
  end;
end;

{=============================================================================
  STRUCTURE (incrément C2-B) — n-grams, histogrammes, classes de caractères
  =============================================================================
  --ngrams=N      : fenêtres glissantes de N mots (1..5) sur les mots du mode
                    courant (--word-mode + --casefold appliqués, cohérent avec
                    --lexical-stats). Les fenêtres NE TRAVERSENT PAS les sauts
                    de ligne : chaque ligne produit ses propres fenêtres.
  --top-ngrams=K  : seuls les top-K sont conservés (défaut 10 ; 0 = tous).
                    Mémoire bornée par un "top-K sketch" : quand le dictionnaire
                    des n-grams dépasse un seuil, il est réduit au top-K (les
                    n-grams rares écartés en cours de route sont perdus —
                    approximation documentée, exacte sur les petits corpus).
  --stopwords=L   : fr | en | none. Listes courtes intégrées (articles, pronoms,
                    conjonctions courants). Les mots vides sont retirés du flux
                    de tokens utilisé pour les n-grams UNIQUEMENT (les
                    statistiques de mots existantes ne sont pas affectées).
                    Matching sur le flux casefoldé (défaut --casefold=ascii).
                    Sans --ngrams, l'option est ignorée silencieusement.
  --histogram=M   : line_length | word_length | words_per_sentence. Classes
                    identiques aux exemples de la roadmap (§6.6) pour
                    line_length (0-9, 10-19, 20-29, 30-39, 40+) ; classes
                    stables définies et documentées pour les deux autres.
  --char-classes  : chaque code point classé UNE seule fois dans
                    letters|digits|whitespace|punctuation|control|other ;
                    la somme des six classes = characters (assertion de test).
  =============================================================================}

const
  // Mots vides français (--stopwords=fr) — 20 entrées, documentées au README.
  FR_STOPWORDS: array[0..19] of string = (
    'le', 'la', 'les', 'un', 'une', 'des', 'de', 'du', 'et', 'ou',
    'mais', 'que', 'qui', 'ce', 'il', 'elle', 'on', 'je', 'tu', 'ne');
  // Mots vides anglais (--stopwords=en) — 20 entrées, documentées au README.
  EN_STOPWORDS: array[0..19] of string = (
    'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on',
    'for', 'with', 'is', 'are', 'was', 'it', 'this', 'that', 'not', 'as');

{-----------------------------------------------------------------------------
  MinInt64 : Minimum de deux entiers 64 bits (évite la dépendance à Math).
  -----------------------------------------------------------------------------}
function MinInt64(A, B: Int64): Int64;
begin
  if A < B then Result := A else Result := B;
end;

{-----------------------------------------------------------------------------
  IsStopWord : Vrai si W appartient à la liste de mots vides de la langue Mode.
  Matching exact sur le token casefoldé (les listes sont en minuscules).
  -----------------------------------------------------------------------------}
function IsStopWord(const W: string; Mode: TStopWord): Boolean;
var
  i: Integer;
begin
  Result := False;
  case Mode of
    swNone: Exit;
    swFR: for i := 0 to High(FR_STOPWORDS) do
            if W = FR_STOPWORDS[i] then Exit(True);
    swEN: for i := 0 to High(EN_STOPWORDS) do
            if W = EN_STOPWORDS[i] then Exit(True);
  end;
end;

{-----------------------------------------------------------------------------
  CharClassOf : Classe d'un code point (--char-classes), plages documentées au
  README (« Sémantique des classes de caractères »). Chaque code point est
  classé une seule fois :
    - whitespace : TAB (U+0009), LF (U+000A), CR (U+000D), espace (U+0020) —
      cohérent avec le compteur tabs (pas « non imprimable ») ;
    - control : C0 hors TAB/LF/CR + DEL (U+007F) + C1 (U+0080..U+009F) ;
    - digits : chiffres ASCII (U+0030..U+0039) ;
    - letters : ASCII, Latin-1 (hors × ÷), Latin étendu A/B, grec (hors
      point-virgule grec), cyrillique, latin étendu additionnel ;
    - punctuation : plages ASCII de ponctuation + ponctuation/symboles Latin-1
      (U+00A1..U+00BF) ;
    - other : tout le reste (symboles, blancs Unicode non-ASCII, U+FFFD…).
  -----------------------------------------------------------------------------}
function CharClassOf(CP: UInt32): Integer;
begin
  // Blancs d'abord (TAB/LF/CR ne sont PAS des contrôles ici)
  if (CP = 9) or (CP = 10) or (CP = 13) or (CP = 32) then Exit(CC_WHITESPACE);
  // Contrôles : C0 hors TAB/LF/CR (déjà blancs), DEL et C1
  if (CP <= $1F) or ((CP >= $7F) and (CP <= $9F)) then Exit(CC_CONTROL);
  // Chiffres : ASCII uniquement
  if (CP >= $30) and (CP <= $39) then Exit(CC_DIGITS);
  // Lettres (plages alignées sur IsUnicodeWordChar, sans les chiffres ni les
  // marques combinantes — celles-ci tombent dans `other`, périmètre documenté)
  if ((CP >= $41) and (CP <= $5A)) or   // A-Z
     ((CP >= $61) and (CP <= $7A)) or   // a-z
     ((CP >= $C0) and (CP <= $D6)) or   // Latin-1 (hors ×)
     ((CP >= $D8) and (CP <= $F6)) or   // Latin-1 (hors ÷)
     ((CP >= $F8) and (CP <= $24F)) or  // Latin étendu A/B
     ((CP >= $370) and (CP <= $3FF) and (CP <> $37E)) or  // Grec
     ((CP >= $400) and (CP <= $4FF)) or // Cyrillique
     ((CP >= $1E00) and (CP <= $1EFF)) then Exit(CC_LETTERS); // Latin étendu additionnel
  // Ponctuation ASCII (U+0021..U+002F, U+003A..U+0040, U+005B..U+0060,
  // U+007B..U+007E) + ponctuation/symboles Latin-1 (U+00A1..U+00BF)
  if ((CP >= $21) and (CP <= $2F)) or
     ((CP >= $3A) and (CP <= $40)) or
     ((CP >= $5B) and (CP <= $60)) or
     ((CP >= $7B) and (CP <= $7E)) or
     ((CP >= $A1) and (CP <= $BF)) then Exit(CC_PUNCTUATION);
  Result := CC_OTHER;
end;

{-----------------------------------------------------------------------------
  HistClassCount : Nombre de classes d'un histogramme (5 pour line_length et
  words_per_sentence, 7 pour word_length).
  -----------------------------------------------------------------------------}
function HistClassCount(Kind: THistogramKind): Integer;
begin
  case Kind of
    hkLineLength:       Result := 5;
    hkWordLength:       Result := 7;
    hkWordsPerSentence: Result := 5;
    else                Result := 0;
  end;
end;

{-----------------------------------------------------------------------------
  HistogramIndex : Indice de classe d'une valeur V selon le type d'histogramme.
  Classes (documentées au README) :
    line_length       : 0-9, 10-19, 20-29, 30-39, 40+ (exemple roadmap §6.6)
    word_length       : 1-2, 3-4, 5-6, 7-8, 9-10, 11-12, 13+
    words_per_sentence: 0-4, 5-9, 10-14, 15-19, 20+
  -----------------------------------------------------------------------------}
function HistogramIndex(Kind: THistogramKind; V: Int64): Integer;
begin
  case Kind of
    hkLineLength:       Result := MinInt64(V div 10, 4);
    hkWordLength:       Result := MinInt64((V - 1) div 2, 6);
    hkWordsPerSentence: Result := MinInt64(V div 5, 4);
    else                Result := 0;
  end;
end;

{-----------------------------------------------------------------------------
  HistogramRanges : Libellés « début-fin » ou « min+ » des classes d'un type
  d'histogramme (ordre = ordre d'affichage/export).
  -----------------------------------------------------------------------------}
function HistogramRanges(Kind: THistogramKind): TStringArray;
var
  i: Integer;
begin
  Result := nil;  // hkNone : tableau vide (jamais exporté)
  SetLength(Result, HistClassCount(Kind));
  case Kind of
    hkLineLength:
      begin
        for i := 0 to 3 do
          Result[i] := IntToStr(10 * i) + '-' + IntToStr(10 * i + 9);
        Result[4] := '40+';
      end;
    hkWordLength:
      begin
        for i := 0 to 5 do
          Result[i] := IntToStr(2 * i + 1) + '-' + IntToStr(2 * i + 2);
        Result[6] := '13+';
      end;
    hkWordsPerSentence:
      begin
        for i := 0 to 3 do
          Result[i] := IntToStr(5 * i) + '-' + IntToStr(5 * i + 4);
        Result[4] := '20+';
      end;
  end;
end;

{-----------------------------------------------------------------------------
  HistogramName : Nom JSON/console du type d'histogramme (soulignés).
  -----------------------------------------------------------------------------}
function HistogramName(Kind: THistogramKind): string;
begin
  case Kind of
    hkLineLength:       Result := 'line_length';
    hkWordLength:       Result := 'word_length';
    hkWordsPerSentence: Result := 'words_per_sentence';
    else                Result := '';
  end;
end;

{-----------------------------------------------------------------------------
  JoinNGramWords : Concatène les mots d'un n-gram avec un espace
  (les tokens ne contiennent jamais d'espace : la jointure est sans ambiguïté).
  -----------------------------------------------------------------------------}
function JoinNGramWords(const Words: TStringArray): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(Words) do
  begin
    if i > 0 then Result := Result + ' ';
    Result := Result + Words[i];
  end;
end;

{-----------------------------------------------------------------------------
  QuickSortNGrams : Tri décroissant par fréquence, puis croissant par clé
  (déterminisme des égalités — ordre d'itération des dictionnaires exclu).
  -----------------------------------------------------------------------------}
procedure QuickSortNGrams(var A: TNGramFreqArray; L, R: Integer);
var
  I, J: Integer;
  P, T: TNGramFreq;
begin
  if L >= R then Exit;  // Tableau vide ou 1 element : rien a trier
  I := L; J := R;
  P := A[(L + R) div 2];
  repeat
    while (A[I].Count > P.Count) or
          ((A[I].Count = P.Count) and (CompareStr(A[I].Key, P.Key) < 0)) do Inc(I);
    while (A[J].Count < P.Count) or
          ((A[J].Count = P.Count) and (CompareStr(A[J].Key, P.Key) > 0)) do Dec(J);
    if I <= J then
    begin
      T := A[I]; A[I] := A[J]; A[J] := T;
      Inc(I); Dec(J);
    end;
  until I > J;
  if L < J then QuickSortNGrams(A, L, J);
  if I < R then QuickSortNGrams(A, I, R);
end;

{-----------------------------------------------------------------------------
  PruneNGrams : Réduit le dictionnaire des n-grams à ses Keep entrées les plus
  fréquentes (mémoire bornée ; les entrées écartées sont perdues — top-K
  approximatif, documenté). Aucun effet si Keep <= 0 (0 = tous).
  -----------------------------------------------------------------------------}
procedure PruneNGrams(Dict: TNGramDict; Keep: Integer);
var
  Arr: TNGramFreqArray;
  Pair: TWordPair;
  i: Integer;
begin
  if Keep <= 0 then Exit;
  SetLength(Arr, Dict.Count);
  i := 0;
  for Pair in Dict do
  begin
    Arr[i].Key := Pair.Key;
    Arr[i].Count := Pair.Value;
    Inc(i);
  end;
  QuickSortNGrams(Arr, 0, High(Arr));
  if Length(Arr) > Keep then SetLength(Arr, Keep);
  Dict.Clear;
  for i := 0 to High(Arr) do
    Dict.Add(Arr[i].Key, Arr[i].Count);
end;

{-----------------------------------------------------------------------------
  AddNGramWindows : Ajoute au dictionnaire toutes les fenêtres de N mots de la
  ligne Tokens, puis applique la borne mémoire du top-K si nécessaire.
  Les fenêtres sont construites par ligne : un saut de ligne « casse » le flux.
  -----------------------------------------------------------------------------}
procedure AddNGramWindows(Dict: TNGramDict; const Tokens: TStringArray;
                          N: Integer; TopK: Integer);
var
  i, j: Integer;
  Key: string;
  C: Int64;
begin
  if Length(Tokens) < N then Exit;
  for i := 0 to Length(Tokens) - N do
  begin
    Key := Tokens[i];
    for j := i + 1 to i + N - 1 do
      Key := Key + ' ' + Tokens[j];
    if Dict.TryGetValue(Key, C) then
      Dict[Key] := C + 1
    else
      Dict.Add(Key, 1);
  end;
  // Borne mémoire : seuil = max(8 × K, 64) entrées avant réduction au top-K.
  // (K > 0 garanti ici : avec --top-ngrams=0 la mémoire est non bornée par
  // choix explicite, comme --top-words=0 / --all.)
  if (TopK > 0) and (Dict.Count > 64) and (Dict.Count > TopK * 8) then
    PruneNGrams(Dict, TopK);
end;

{-----------------------------------------------------------------------------
  BuildNGrams : Convertit le dictionnaire en tableau top-K trié (fréquence
  décroissante, puis clé croissante). Chaque clé (mots séparés par ' ') est
  découpée en tableau de mots pour l'export JSON.
  -----------------------------------------------------------------------------}
procedure BuildNGrams(Dict: TNGramDict; TopK: Integer; var OutArr: TNGramFreqArray);
var
  Arr: TNGramFreqArray;
  i, Limit, p, q: Integer;
  Pair: TWordPair;
  W: string;
begin
  SetLength(Arr, Dict.Count);
  i := 0;
  for Pair in Dict do
  begin
    Arr[i].Key := Pair.Key;
    Arr[i].Count := Pair.Value;
    Inc(i);
  end;
  QuickSortNGrams(Arr, 0, High(Arr));
  Limit := Length(Arr);
  if (TopK > 0) and (Limit > TopK) then Limit := TopK;
  SetLength(OutArr, Limit);
  for i := 0 to Limit - 1 do
  begin
    OutArr[i].Count := Arr[i].Count;
    OutArr[i].Key := Arr[i].Key;
    W := Arr[i].Key;
    p := 1;
    while p <= Length(W) do
    begin
      q := p;
      while (q <= Length(W)) and (W[q] <> ' ') do Inc(q);
      SetLength(OutArr[i].Words, Length(OutArr[i].Words) + 1);
      OutArr[i].Words[High(OutArr[i].Words)] := Copy(W, p, q - p);
      p := q + 1;
    end;
  end;
end;

{=============================================================================
  ANALYSE PRINCIPALE - CŒUR DU PROGRAMME
  =============================================================================
  Objectif : Analyser un fichier et remplir la structure TStats
  Performance : Utilisation de dictionnaires hashés pour O(1) par opération
  Sécurité : Gestion robuste des erreurs de lecture, validation UTF-8 stricte
  =============================================================================}
procedure AnalyzeData(const Path: string; Stream: TStream; out Stats: TStats;
                      OptAll: Boolean; WordMode: TWordMode; CaseFoldMode: TCaseFold;
                      MaxUnique: Int64; const SOpts: TStructureOptions);
var
  Buffer: array[0..BUF_SIZE - 1] of Byte;
  ReadBytes, Pos, Used, i: Integer;
  CP: UInt32;
  InWord: Boolean;
  IsWordChar: Boolean;
  CurrentWord, CurrentLine: string;
  LineLen, TotalLen, NonEmpty: Int64;
  LastCPWasCR: Boolean;
  PendingSentence: Boolean;  // Contenu non-blanc depuis le dernier terminateur de phrase
  FirstChar: Boolean;        // Vrai tant que le premier caractère du flux n'est pas consommé (BOM)
  
  // Dictionnaires hashés pour accumulation O(1) - CLÉ DE PERFORMANCE
  CharDict: TCharDict;
  WordDict: TWordDict;
  NGramDict: TNGramDict;     // Comptes des n-grams (C2-B, alloué si NGramSize > 0)
  LineTokens: TStringArray;  // Tokens de la ligne courante (flux n-gram, C2-B)
  SentenceWords: Int64;      // Mots de la phrase courante (words_per_sentence, C2-B)
  PairC: TCharPair;
  PairW: TWordPair;
  Count: Int64;
  MaxLines: Integer;  // 0 = mode --all, sinon limite Top N

  // Clôture le token courant : mise à jour des fréquences (sous la borne
  // --max-unique) et des compteurs. Un token jamais stocké compte quand même
  // dans WordCount et WordCharsTotal (sémantique documentée : unique_words
  // plafonné, non exhaustif).
  procedure FlushWord;
  var
    C: Int64;
    WL: Integer;
  begin
    if WordDict.TryGetValue(CurrentWord, C) then
      WordDict[CurrentWord] := C + 1
    else if WordDict.Count < MaxUnique then
      WordDict.Add(CurrentWord, 1);
    Inc(Stats.WordCount);
    WL := UTF8Length(CurrentWord);
    Inc(Stats.WordCharsTotal, WL);
    // C2-C : comptage des mots longs (>= LONG_WORD_MIN_LEN code points) pour
    // pct_long_words. Accumulé sans condition (comme WordCharsTotal) : le
    // coût est une comparaison par token, et la longueur WL est déjà connue.
    if WL >= LONG_WORD_MIN_LEN then Inc(Stats.LongWordCount);
    // C2-B : histogramme word_length (longueur en code points, cohérent avec
    // average_word_length), mot de la phrase courante (words_per_sentence) et,
    // sauf s'il s'agit d'un mot vide (--stopwords), flux n-gram de la ligne.
    // Les statistiques de mots existantes ne sont pas affectées.
    if SOpts.HistogramKind = hkWordLength then
      Inc(Stats.HistCounts[HistogramIndex(hkWordLength, WL)]);
    Inc(SentenceWords);
    if (SOpts.NGramSize > 0) and (not IsStopWord(CurrentWord, SOpts.StopWordMode)) then
    begin
      SetLength(LineTokens, Length(LineTokens) + 1);
      LineTokens[High(LineTokens)] := CurrentWord;
    end;
    CurrentWord := '';
    InWord := False;
  end;
begin
  // Initialisation de la structure de sortie
  Stats.Path := Path;

  // Préparation des tableaux de sortie (vides au départ)
  SetLength(Stats.Freq, 0);
  SetLength(Stats.Words, 0);
  SetLength(Stats.TopLines, 0);
  SetLength(Stats.NGrams, 0);

  // Création des dictionnaires pour l'accumulation rapide
  CharDict := TCharDict.Create;
  WordDict := TWordDict.Create;
  NGramDict := nil;
  if SOpts.NGramSize > 0 then
    NGramDict := TNGramDict.Create;

  // Initialisation des compteurs et états
  Stats.LineCount := 0;
  Stats.WordCount := 0;
  Stats.CharCount := 0;
  Stats.SentenceCount := 0;
  Stats.AvgWordsPerSentence := 0;
  // Compteurs qualité (incrément A) : initialisés avant l'analyse
  Stats.InvalidUTF8 := 0;
  Stats.BOM := False;
  Stats.CRLF := 0;
  Stats.Tabs := 0;
  Stats.NonPrintable := 0;
  Stats.UniqueWords := 0;      // Types de mots stockés (rempli en fin d'analyse)
  Stats.WordCharsTotal := 0;   // Somme des longueurs de tous les tokens
  Stats.LongWordCount := 0;    // Tokens de >= 7 code points (--readability, C2-C)
  // Structure (incrément C2-B) : état des sections optionnelles
  Stats.NGramSize := SOpts.NGramSize;
  Stats.CharClassesEnabled := SOpts.CharClasses;
  Stats.HistogramKind := SOpts.HistogramKind;
  Stats.HistRanges := HistogramRanges(SOpts.HistogramKind);
  SetLength(Stats.HistCounts, HistClassCount(SOpts.HistogramKind));
  for i := 0 to High(Stats.HistCounts) do
    Stats.HistCounts[i] := 0;
  for i := 0 to CC_CLASS_COUNT - 1 do
    Stats.CharClasses[i] := 0;
  SentenceWords := 0;
  SetLength(LineTokens, 0);
  FirstChar := True;
  InWord := False;
  CurrentWord := '';
  LastCPWasCR := False;
  PendingSentence := False;
  CurrentLine := '';
  Stats.MinLen := High(Int64);  // Pour trouver le minimum
  Stats.MaxLen := 0;            // Pour trouver le maximum
  TotalLen := 0;
  NonEmpty := 0;
  LineLen := 0;
  
  // Détermination du mode : --all ou Top N
  if OptAll then
    MaxLines := 0
  else
    MaxLines := DEFAULT_TOP_LIMIT;

  try
    // Boucle principale de lecture par blocs (fichier ou entrée standard)
    repeat
      ReadBytes := Stream.Read(Buffer, BUF_SIZE);
      Pos := 0;

      // Traitement octet par octet du buffer courant
      while Pos < ReadBytes do
      begin
        // Décodage UTF-8 avec validation stricte
        if not DecodeUTF8(@Buffer[Pos], ReadBytes - Pos, CP, Used) then
        begin
          // Caractère invalide : utiliser le caractère de remplacement
          CP := $FFFD;
          Used := 1;
          Inc(Stats.InvalidUTF8);  // Compter la séquence invalide (incrément A)
        end;

        Inc(Pos, Used);        // Avancer dans le buffer
        Inc(Stats.CharCount);  // Compter le caractère

        // Détection du BOM (U+FEFF) : uniquement le tout premier caractère
        if FirstChar then
        begin
          Stats.BOM := (CP = $FEFF);
          FirstChar := False;
        end;

        // Compteurs qualité : tabulations et caractères de contrôle
        if CP = 9 then Inc(Stats.Tabs);
        if ((CP <= $1F) and (CP <> 9) and (CP <> 10) and (CP <> 13)) or (CP = $7F) then
          Inc(Stats.NonPrintable);

        // Classes de caractères (--char-classes, C2-B) : chaque code point est
        // classé exactement une fois ; la somme des classes = characters.
        if SOpts.CharClasses then
          Inc(Stats.CharClasses[CharClassOf(CP)]);

        // Accumulation dans le dictionnaire de caractères (O(1))
        if CharDict.TryGetValue(CP, Count) then
          CharDict[CP] := Count + 1
        else
          CharDict.Add(CP, 1);

        // Comptage des phrases : un terminateur est '.' (U+002E), '!'
        // (U+0021), '?' (U+003F) ou '…' (U+2026). Chaque terminateur rencontré
        // clôt une phrase (le compteur s'incrémente ici). PendingSentence
        // mémorise les caractères non-blancs situés après le dernier
        // terminateur, pour compter l'éventuelle phrase finale en fin de fichier.
        // C2-B : l'histogramme words_per_sentence reçoit le nombre de mots de
        // la phrase qui se clôt (0 pour une phrase vide, ex. terminuteurs
        // consécutifs : la somme des classes reste égale à sentences).
        if (CP = $2E) or (CP = $21) or (CP = $3F) or (CP = $2026) then
        begin
          Inc(Stats.SentenceCount);
          if SOpts.HistogramKind = hkWordsPerSentence then
            Inc(Stats.HistCounts[HistogramIndex(hkWordsPerSentence, SentenceWords)]);
          SentenceWords := 0;
          PendingSentence := False;
        end
        else if (CP > $20) and (CP <> $FFFD) then
          PendingSentence := True;

        // Gestion des sauts de ligne (CRLF, LF, CR)
        if (CP = 10) and LastCPWasCR then
        begin
          Inc(Stats.CRLF);  // Fin de ligne CRLF détectée (incrément A)
          LastCPWasCR := False;
          Continue;  // Ignorer le LF qui suit un CR (CRLF)
        end;

        if (CP = 10) or (CP = 13) then
        begin
          // Fin de ligne détectée
          Inc(Stats.LineCount);
          AddLine(Stats.TopLines, CurrentLine, LineLen, MaxLines);
          
          // Mise à jour des statistiques de longueur
          if LineLen > 0 then
          begin
            Inc(NonEmpty);
            Inc(TotalLen, LineLen);
            if LineLen < Stats.MinLen then Stats.MinLen := LineLen;
            if LineLen > Stats.MaxLen then Stats.MaxLen := LineLen;
          end;

          // C2-B : histogramme line_length (toutes les lignes, vides comprises)
          if SOpts.HistogramKind = hkLineLength then
            Inc(Stats.HistCounts[HistogramIndex(hkLineLength, LineLen)]);
          
          // Réinitialisation pour la prochaine ligne
          CurrentLine := '';
          LineLen := 0;
          LastCPWasCR := (CP = 13);

          // Fin de mot si on était dans un mot
          if InWord then FlushWord;

          // C2-B : fenêtres n-gram de la ligne courante — un saut de ligne
          // « casse » le flux : aucun n-gram ne traverse la fin de ligne.
          if SOpts.NGramSize > 0 then
          begin
            AddNGramWindows(NGramDict, LineTokens, SOpts.NGramSize,
                            SOpts.TopNgramsLimit);
            SetLength(LineTokens, 0);
          end;
        end
        else
        begin
          // Caractère normal (pas un saut de ligne)
          LastCPWasCR := False;
          CurrentLine := CurrentLine + VisualChar(CP);  // Ajouter à la ligne courante
          Inc(LineLen);

          // Détection des caractères de mot selon --word-mode ; tout le reste
          // (blancs, contrôles, ponctuation selon le mode) sépare les mots.
          IsWordChar := False;
          case WordMode of
            wmRaw:     IsWordChar := (CP > $20) and (CP <> $FFFD);
            wmAscii:   IsWordChar := IsAsciiWordChar(CP);
            wmUnicode: IsWordChar := IsUnicodeWordChar(CP);
          end;

          if not IsWordChar then
          begin
            // Séparateur : clôt le mot courant s'il y en a un
            if InWord then FlushWord;
          end
          else
          begin
            // Caractère faisant partie d'un mot : repli de casse appliqué
            // AVANT l'encodage UTF-8 (--casefold)
            InWord := True;
            CurrentWord := CurrentWord + VisualChar(FoldChar(CP, CaseFoldMode));
          end;
        end;
      end;
    until ReadBytes = 0;  // Fin du fichier

    // Traitement de la dernière ligne si le fichier ne termine pas par un saut de ligne
    if LineLen > 0 then
    begin
      Inc(Stats.LineCount);
      AddLine(Stats.TopLines, CurrentLine, LineLen, MaxLines);
      Inc(NonEmpty);
      Inc(TotalLen, LineLen);
      if LineLen < Stats.MinLen then Stats.MinLen := LineLen;
      if LineLen > Stats.MaxLen then Stats.MaxLen := LineLen;
      if SOpts.HistogramKind = hkLineLength then
        Inc(Stats.HistCounts[HistogramIndex(hkLineLength, LineLen)]);
    end;

    // Traitement du dernier mot si le fichier ne termine pas par un séparateur
    if InWord then FlushWord;

    // C2-B : fenêtres n-gram de la dernière ligne (le dernier mot y est inclus)
    if SOpts.NGramSize > 0 then
    begin
      AddNGramWindows(NGramDict, LineTokens, SOpts.NGramSize, SOpts.TopNgramsLimit);
      SetLength(LineTokens, 0);
    end;

    // Phrase finale : si le fichier se termine avec du contenu non-blanc
    // après le dernier terminateur, on compte une phrase supplémentaire (et
    // l'histogramme words_per_sentence reçoit les mots de cette phrase).
    if PendingSentence then
    begin
      Inc(Stats.SentenceCount);
      if SOpts.HistogramKind = hkWordsPerSentence then
        Inc(Stats.HistCounts[HistogramIndex(hkWordsPerSentence, SentenceWords)]);
    end;

    // Conversion des dictionnaires en tableaux pour le tri final
    SetLength(Stats.Freq, CharDict.Count);
    i := 0;
    for PairC in CharDict do
    begin
      Stats.Freq[i].CodePoint := PairC.Key;
      Stats.Freq[i].Count := PairC.Value;
      Inc(i);
    end;
    
    SetLength(Stats.Words, WordDict.Count);
    i := 0;
    for PairW in WordDict do
    begin
      Stats.Words[i].Word := PairW.Key;
      Stats.Words[i].Count := PairW.Value;
      Inc(i);
    end;

    // Nombre de types de mots stockés (plafonné par --max-unique le cas échéant)
    Stats.UniqueWords := WordDict.Count;

    // C2-B : conversion du dictionnaire n-gram en tableau top-K (tri par
    // fréquence décroissante, puis par clé pour des égalités déterministes)
    if SOpts.NGramSize > 0 then
      BuildNGrams(NGramDict, SOpts.TopNgramsLimit, Stats.NGrams);

  finally
    // Nettoyage obligatoire des ressources (mémoire ; le flux d'entrée est
    // fermé par l'appelant : AnalyzeFile/AnalyzeStdin)
    CharDict.Free;
    WordDict.Free;
    if NGramDict <> nil then NGramDict.Free;
  end;

  // Calcul de la moyenne de longueur de ligne (protection division par zéro)
  if NonEmpty > 0 then
    Stats.AvgLen := TotalLen div NonEmpty
  else
    Stats.AvgLen := 0;
    
  // Correction de MinLen si aucune ligne non vide n'a été trouvée
  if Stats.MinLen = High(Int64) then
    Stats.MinLen := 0;

  // Moyenne de mots par phrase (protection division par zéro)
  if Stats.SentenceCount > 0 then
    Stats.AvgWordsPerSentence := Stats.WordCount div Stats.SentenceCount
  else
    Stats.AvgWordsPerSentence := 0;

  // Tri final des tableaux pour l'affichage/export (décroissant par fréquence/longueur)
  if Length(Stats.Freq) > 0 then
    QuickSortChars(Stats.Freq, 0, High(Stats.Freq));
  if Length(Stats.Words) > 0 then
    QuickSortWords(Stats.Words, 0, High(Stats.Words));
  // Les lignes sont déjà triées si MaxLines > 0, sinon on trie si --all
  if (MaxLines <= 0) and (Length(Stats.TopLines) > 0) then
    QuickSortLines(Stats.TopLines, 0, High(Stats.TopLines));
end;

{-----------------------------------------------------------------------------
  AnalyzeFile : Ouvre un fichier en lecture binaire et l'analyse.
  Erreurs  : lève EFOpenError/EInOutError si le fichier est inaccessible
             (interceptées par l'appelant pour un message clair).
  -----------------------------------------------------------------------------}
procedure AnalyzeFile(const Path: string; out Stats: TStats; OptAll: Boolean;
                      WordMode: TWordMode; CaseFoldMode: TCaseFold; MaxUnique: Int64;
                      const SOpts: TStructureOptions);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    AnalyzeData(Path, FS, Stats, OptAll, WordMode, CaseFoldMode, MaxUnique, SOpts);
  finally
    FS.Free;
  end;
end;

{-----------------------------------------------------------------------------
  AnalyzeStdin : Analyse l'entrée standard en binaire (stdin).
  Path affiché : 'stdin'. THandleStream ne possède pas le handle : il n'est
  donc pas fermé ici.
  -----------------------------------------------------------------------------}
procedure AnalyzeStdin(out Stats: TStats; OptAll: Boolean;
                       WordMode: TWordMode; CaseFoldMode: TCaseFold; MaxUnique: Int64;
                       const SOpts: TStructureOptions);
var
  HS: THandleStream;
begin
  HS := THandleStream.Create(StdInputHandle);
  try
    AnalyzeData('stdin', HS, Stats, OptAll, WordMode, CaseFoldMode, MaxUnique, SOpts);
  finally
    HS.Free;
  end;
end;

{=============================================================================
  STATISTIQUES LEXICALES (incrément C2-A) — calcul et formatage
  =============================================================================
  --lexical-stats ajoute : unique_words, hapax, type_token_ratio,
  average_word_length, entropy_bits_per_word. Formules figées dans le README
  (« Sémantique lexicale »).
  =============================================================================}

{-----------------------------------------------------------------------------
  FormatFloatTrim : Formate un Double avec au plus Decimals décimales, en
  tronquant les zéros de fin, avec '.' comme séparateur décimal — indépendant
  de la locale (JSON valide, console ASCII). Ex. : 0.9230769 -> "0.923077".
  -----------------------------------------------------------------------------}
function FormatFloatTrim(V: Double; Decimals: Integer): string;
var
  Scale, IVal, IntP, FracP: Int64;
  FracS: string;
  k: Integer;
begin
  if V = 0 then Exit('0');
  if V < 0 then V := -V;   // Les métriques lexicales sont non négatives
  Scale := 1;
  for k := 1 to Decimals do Scale := Scale * 10;
  IVal := Round(V * Scale);
  IntP := IVal div Scale;
  FracP := IVal mod Scale;
  FracS := IntToStr(FracP);
  while Length(FracS) < Decimals do FracS := '0' + FracS;
  while (Length(FracS) > 0) and (FracS[Length(FracS)] = '0') do
    Delete(FracS, Length(FracS), 1);
  Result := IntToStr(IntP);
  if FracS <> '' then Result := Result + '.' + FracS;
end;

{-----------------------------------------------------------------------------
  EffectiveLimit : Nombre d'éléments d'une section à afficher/exporter.
  ShowAll (--all) ou TopLimit <= 0 (--top-words=0 / --top-chars=0) : tout ;
  sinon min(TopLimit, Total). Les valeurs calculées restent identiques.
  -----------------------------------------------------------------------------}
function EffectiveLimit(Total: Integer; ShowAll: Boolean; TopLimit: Integer): Integer;
begin
  if ShowAll or (TopLimit <= 0) then
    Result := Total
  else if TopLimit < Total then
    Result := TopLimit
  else
    Result := Total;
end;

{-----------------------------------------------------------------------------
  ComputeLexical : Calcule les statistiques lexicales depuis TStats.
  Formules (README) : TTR = types/tokens ; hapax = types à fréquence 1 ;
  longueur moyenne = code points par token ; entropie = -Σ p_i log2 p_i sur
  les types du mode courant. Sous --max-unique, les valeurs portent sur le
  jeu de types STOCKÉS (unique_words plafonné, non exhaustif — documenté).
  -----------------------------------------------------------------------------}
function ComputeLexical(const Stats: TStats): TLexicalStats;
var
  i: Integer;
  P: Double;
  Log2: Double;
begin
  Result.UniqueWords := Stats.UniqueWords;
  Result.Hapax := 0;
  for i := 0 to High(Stats.Words) do
    if Stats.Words[i].Count = 1 then Inc(Result.Hapax);
  if Stats.WordCount > 0 then
  begin
    Result.TypeTokenRatio := Stats.UniqueWords / Stats.WordCount;
    Result.AverageWordLength := Stats.WordCharsTotal / Stats.WordCount;
  end
  else
  begin
    Result.TypeTokenRatio := 0;
    Result.AverageWordLength := 0;
  end;
  Result.EntropyBitsPerWord := 0;
  if (Stats.WordCount > 0) and (Length(Stats.Words) > 0) then
  begin
    Log2 := Ln(2);
    for i := 0 to High(Stats.Words) do
    begin
      P := Stats.Words[i].Count / Stats.WordCount;
      Result.EntropyBitsPerWord := Result.EntropyBitsPerWord - P * (Ln(P) / Log2);
    end;
  end;
end;

{-----------------------------------------------------------------------------
  ComputeReadability : Calcule les statistiques de lisibilité depuis TStats.
  Métriques (mode courant = --word-mode + --casefold, comme --lexical-stats) :
    avg_sentence_words = WordCount / SentenceCount (0 si aucune phrase)
    avg_word_chars     = WordCharsTotal / WordCount (0 si aucun mot)
    pct_long_words     = 100 * LongWordCount / WordCount (0 si aucun mot)
    score              = 100 * (1 - (0.5 * min(ASL/30, 1)
                             + 0.5 * min(max(ALW-3, 0)/5, 1)))
  où ASL = avg_sentence_words et ALW = avg_word_chars. Formule EXACTE,
  inspirée de Flesch mais SANS syllabes (aucune détection de syllabes en
  français). Ancrages : une phrase de 30+ mots en moyenne (ASL >= 30) ou des
  mots de 8+ caractères en moyenne (ALW >= 8) annulent chacun la MOITIÉ du
  score (terme borné à 1). Score plafonné à [0, 100] ; un texte sans aucun
  mot (fichier vide) a un score de 0 (pas de matière à évaluer).
  -----------------------------------------------------------------------------}
function ComputeReadability(const Stats: TStats): TReadabilityStats;
var
  Asl, Alw: Double;
begin
  if Stats.SentenceCount > 0 then
    Result.AvgSentenceWords := Stats.WordCount / Stats.SentenceCount
  else
    Result.AvgSentenceWords := 0;
  if Stats.WordCount > 0 then
  begin
    Result.AvgWordChars := Stats.WordCharsTotal / Stats.WordCount;
    Result.PctLongWords := 100 * Stats.LongWordCount / Stats.WordCount;
  end
  else
  begin
    Result.AvgWordChars := 0;
    Result.PctLongWords := 0;
  end;
  // Score : 0 si aucun mot (sinon la formule ci-dessus donnerait 100 pour un
  // fichier vide — sémantique documentée : pas de score sans texte).
  if Stats.WordCount = 0 then
    Result.Score := 0
  else
  begin
    Asl := Result.AvgSentenceWords;
    Alw := Result.AvgWordChars;
    // min(ASL/30, 1) : ASL plafonné à 30.
    if Asl > 30 then Asl := 30;
    // max(ALW-3, 0) : borne inférieure à 0, puis min(..., 1) : (ALW-3)/5
    // plafonné à 1 (ALW plafonné à 8).
    if Alw < 3 then Alw := 3;
    if Alw > 8 then Alw := 8;
    Result.Score := 100 * (1 - (0.5 * (Asl / 30) + 0.5 * ((Alw - 3) / 5)));
    // Clamp de sécurité dans [0, 100] (la formule est bornée par construction).
    if Result.Score < 0 then Result.Score := 0;
    if Result.Score > 100 then Result.Score := 100;
  end;
end;

{=============================================================================
  MOTEUR DE CHECKS ET COMPARAISON BASELINE (Cible 1, incréments B et C,
  v2.6.0) — « le juge » et « la mémoire »
  =============================================================================
  --check            : active le mode check. Mode check IMPLICITE : --fail-if,
                       --warn-if, --compare ou --fail-on-delta l'activent aussi.
  --fail-if SPEC     : check bloquant (statut fail -> exit 2).
  --warn-if SPEC     : check non bloquant (statut warn -> exit 3 si aucun fail).
  Grammaire FIGÉE d'une SPEC (--fail-if et --warn-if), documentée ici :
      SPEC        := METRIQUE [espaces] OPERATEUR [espaces] SEUIL
      METRIQUE    := [a-z0-9_]+            (liste figée ci-dessous)
      OPERATEUR   := '>' | '>=' | '<' | '<=' | '=' | '!='
      SEUIL       := [0-9]+ ('.' [0-9]+)?   (entier ou décimal, '.' séparateur,
                     sans signe ni exposant, indépendant de la locale)
    La SPEC est acceptée en un seul argument (--fail-if lines>5,
    --fail-if "lines > 5") ou en arguments séparés (--fail-if lines > 5).
  Métriques du gate (valeurs depuis TStats, toutes entières) :
      lines, words, sentences, max_line_length (Stats.MaxLen),
      avg_words_per_sentence (Stats.AvgWordsPerSentence — division entière,
      sémantique figée du Summary ; alias accepté : avg_sentence_words),
      non_utf8 (Stats.InvalidUTF8), bom (0/1), crlf, tabs, nonprintable.
    Toute autre métrique -> erreur fatale exit 1 (message stderr français).
  Statut d'un check : ok | warn | fail — comparaison numérique stricte
  (actual OPERATEUR SEUIL). Multi-fichiers : le pire statut gagne
  (fail > warn > ok). Exit codes (mode check uniquement ; le mode analyse
  garde 0/1) : 0 = tout ok (ou aucun check défini), 2 = au moins un fail,
  3 = aucun fail mais au moins un warn, 1 = erreur fatale (prime sur tout).

  --compare BASELINE : lit une baseline NDJSON produite par --summary-json
    (une ligne JSON par fichier, clé "file" ; un objet unique est accepté).
    Chaque ligne doit être un objet JSON avec la clé "file", sinon erreur
    fatale exit 1. Correspondance par comparaison EXACTE de la chaîne
    "file" avec le chemin affiché par fstats ('stdin' fonctionne aussi).
    Fichier analysé sans baseline -> les checks delta sont IGNORÉS pour ce
    fichier (pas d'erreur, documenté) ; lignes baseline sans fichier
    analysé -> ignorées.
  --fail-on-delta SPEC : check de dérive, opérateur '>' IMPOSÉ, seuil en %
    décimal. SPEC := METRIQUE '>' SEUIL (espaces acceptés autour).
    delta = (actual - base) / base * 100, actual = valeur courante,
    base = valeur de la baseline. base = 0 : actual = 0 -> delta 0 (ok),
    actual > 0 -> dérive INFINIE -> le check échoue (documenté).
    Métriques delta autorisées : clés numériques du summary-json — lines,
    words, characters, sentences, avg_words_per_sentence (alias
    avg_sentence_words), line_min, line_max, line_avg, invalid_utf8 (alias
    non_utf8), bom, crlf, tabs, nonprintable. Toute autre -> exit 1.
    --fail-on-delta sans --compare -> erreur fatale exit 1.
  Sorties : section "Checks" console insérée après la section Summary ;
    JSON pretty/compact : bloc additif "checks" après "quality", avant les
    blocs additifs. --summary-json et --csv : INCHANGÉS (pas de section
    checks — les exit codes s'appliquent quand même). --json-mode=aggregate :
    checks dans les objets par fichier, jamais dans "totals".
  =============================================================================}

{-----------------------------------------------------------------------------
  OpToStr : Représentation texte d'un opérateur de check ('>', '>=', ...).
  -----------------------------------------------------------------------------}
function OpToStr(Op: TCheckOp): string;
begin
  case Op of
    opGt: Result := '>';
    opGe: Result := '>=';
    opLt: Result := '<';
    opLe: Result := '<=';
    opEq: Result := '=';
    opNe: Result := '!=';
  end;
end;

{-----------------------------------------------------------------------------
  CheckStatusStr : Statut d'un check en texte — minuscules pour le JSON
  ('ok'|'warn'|'fail'), majuscules pour la console ('OK'|'WARN'|'FAIL').
  -----------------------------------------------------------------------------}
function CheckStatusStr(St: TCheckStatus; Upper: Boolean): string;
begin
  case St of
    csOk:   if Upper then Result := 'OK'   else Result := 'ok';
    csWarn: if Upper then Result := 'WARN' else Result := 'warn';
    csFail: if Upper then Result := 'FAIL' else Result := 'fail';
  end;
end;

{-----------------------------------------------------------------------------
  IsValidMetricName : Vrai si M est un nom de métrique syntaxiquement valide,
  c'est-à-dire uniquement [a-z0-9_] (grammaire figée).
  -----------------------------------------------------------------------------}
function IsValidMetricName(const M: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  if M = '' then Exit;
  for i := 1 to Length(M) do
    if not (((M[i] >= 'a') and (M[i] <= 'z')) or
            ((M[i] >= '0') and (M[i] <= '9')) or (M[i] = '_')) then Exit;
  Result := True;
end;

{-----------------------------------------------------------------------------
  ContainsCheckOp : Vrai si S contient un des caractères d'opérateur
  (>, <, =, !). Distingue "metric>seuil" de "metric" seul (opérateur passé
  en argument séparé de --fail-if/--warn-if/--fail-on-delta).
  -----------------------------------------------------------------------------}
function ContainsCheckOp(const S: string): Boolean;
var
  i: Integer;
begin
  for i := 1 to Length(S) do
    if (S[i] = '>') or (S[i] = '<') or (S[i] = '=') or (S[i] = '!') then
      Exit(True);
  Result := False;
end;

{-----------------------------------------------------------------------------
  IsOpToken : Vrai si S est exactement un opérateur de la grammaire.
  -----------------------------------------------------------------------------}
function IsOpToken(const S: string): Boolean;
begin
  Result := (S = '>') or (S = '>=') or (S = '<') or (S = '<=') or
            (S = '=') or (S = '!=');
end;

{-----------------------------------------------------------------------------
  ParseNumber : Parse un seuil numérique — grammaire figée
  [0-9]+ ('.' [0-9]+)? : entier ou décimal, '.' séparateur, sans signe ni
  exposant, indépendant de la locale (aucune dépendance à DecimalSeparator).
  -----------------------------------------------------------------------------}
function ParseNumber(const S: string; out V: Double): Boolean;
var
  i: Integer;
  Scale: Double;
  SeenDot, SeenDigit: Boolean;
begin
  Result := False;
  V := 0;
  if S = '' then Exit;
  Scale := 10;
  SeenDot := False;
  SeenDigit := False;
  for i := 1 to Length(S) do
  begin
    case S[i] of
      '0'..'9':
        begin
          SeenDigit := True;
          if not SeenDot then
            V := V * 10 + (Ord(S[i]) - 48)
          else
          begin
            V := V + (Ord(S[i]) - 48) / Scale;
            Scale := Scale * 10;
          end;
        end;
      '.':
        if SeenDot then Exit   // deux points décimaux : invalide
        else SeenDot := True;
      else Exit;               // caractère non numérique : invalide
    end;
  end;
  Result := SeenDigit;
end;

{-----------------------------------------------------------------------------
  CanonMetricFailIf : Normalise une métrique du gate (--fail-if/--warn-if).
  Alias acceptés : avg_sentence_words -> avg_words_per_sentence ;
  invalid_utf8 -> non_utf8 (nom JSON du summary). Retourne ''
  si la métrique est inconnue (erreur fatale chez l'appelant).
  -----------------------------------------------------------------------------}
function CanonMetricFailIf(const M: string): string;
begin
  if (M = 'lines') or (M = 'words') or (M = 'sentences') or
     (M = 'max_line_length') or (M = 'non_utf8') or (M = 'invalid_utf8') or
     (M = 'bom') or (M = 'crlf') or (M = 'tabs') or (M = 'nonprintable') then
    Result := M
  else if (M = 'avg_words_per_sentence') or (M = 'avg_sentence_words') then
    Result := 'avg_words_per_sentence'
  else
    Result := '';
end;

{-----------------------------------------------------------------------------
  CanonMetricDelta : Normalise une métrique de dérive (--fail-on-delta).
  Les noms canoniques sont les clés numériques du summary-json :
  avg_words_per_sentence (alias avg_sentence_words), invalid_utf8 (alias
  non_utf8). Retourne '' si inconnue.
  -----------------------------------------------------------------------------}
function CanonMetricDelta(const M: string): string;
begin
  if (M = 'lines') or (M = 'words') or (M = 'characters') or
     (M = 'sentences') or (M = 'line_min') or (M = 'line_max') or
     (M = 'line_avg') or (M = 'bom') or (M = 'crlf') or (M = 'tabs') or
     (M = 'nonprintable') then
    Result := M
  else if (M = 'avg_words_per_sentence') or (M = 'avg_sentence_words') then
    Result := 'avg_words_per_sentence'
  else if (M = 'invalid_utf8') or (M = 'non_utf8') then
    Result := 'invalid_utf8'
  else
    Result := '';
end;

{-----------------------------------------------------------------------------
  CheckMetricValue : Valeur courante d'une métrique depuis TStats (entiers
  convertis en Double ; bom booléen -> 1/0). Retourne False si inconnue.
  Couvre l'union des métriques du gate (--fail-if) et du summary (delta).
  -----------------------------------------------------------------------------}
function CheckMetricValue(const Stats: TStats; const Metric: string;
                          out V: Double): Boolean;
begin
  Result := True;
  if Metric = 'lines' then V := Stats.LineCount
  else if Metric = 'words' then V := Stats.WordCount
  else if Metric = 'characters' then V := Stats.CharCount
  else if Metric = 'sentences' then V := Stats.SentenceCount
  else if Metric = 'avg_words_per_sentence' then V := Stats.AvgWordsPerSentence
  else if Metric = 'max_line_length' then V := Stats.MaxLen
  else if Metric = 'line_min' then V := Stats.MinLen
  else if Metric = 'line_max' then V := Stats.MaxLen
  else if Metric = 'line_avg' then V := Stats.AvgLen
  else if (Metric = 'non_utf8') or (Metric = 'invalid_utf8') then
    V := Stats.InvalidUTF8
  else if Metric = 'bom' then
  begin
    if Stats.BOM then V := 1 else V := 0;
  end
  else if Metric = 'crlf' then V := Stats.CRLF
  else if Metric = 'tabs' then V := Stats.Tabs
  else if Metric = 'nonprintable' then V := Stats.NonPrintable
  else Result := False;
end;

{-----------------------------------------------------------------------------
  EvalCompare : Comparaison numérique stricte actual OPERATEUR seuil.
  -----------------------------------------------------------------------------}
function EvalCompare(Actual: Double; Op: TCheckOp; Threshold: Double): Boolean;
begin
  case Op of
    opGt: Result := Actual > Threshold;
    opGe: Result := Actual >= Threshold;
    opLt: Result := Actual < Threshold;
    opLe: Result := Actual <= Threshold;
    opEq: Result := Actual = Threshold;
    opNe: Result := Actual <> Threshold;
  end;
end;

{-----------------------------------------------------------------------------
  FormatFloatTrimSigned : FormatFloatTrim en conservant le signe (les deltas
  de dérive peuvent être négatifs ; FormatFloatTrim prend la valeur absolue).
  -----------------------------------------------------------------------------}
function FormatFloatTrimSigned(V: Double; Decimals: Integer): string;
begin
  if V < 0 then
    Result := '-' + FormatFloatTrim(-V, Decimals)
  else
    Result := FormatFloatTrim(V, Decimals);
end;

{-----------------------------------------------------------------------------
  ParseCheckSpec : Parse une SPEC de check (--fail-if / --warn-if).
  Grammaire figée (voir l'en-tête du moteur) : METRIQUE [espaces] OPERATEUR
  [espaces] SEUIL. Retour : 0 = OK ; 1 = métrique manquante/invalide ;
  2 = opérateur absent ; 3 = opérateur inconnu ; 4 = seuil non numérique ;
  5 = métrique inconnue (Metric contient alors le nom reçu).
  -----------------------------------------------------------------------------}
function ParseCheckSpec(const Arg: string; out Metric: string; out Op: TCheckOp;
                        out Threshold: Double): Integer;
var
  M, OpS, ThrS: string;
  p, i: Integer;
begin
  Result := 0;
  M := Trim(Arg);
  // Localiser le premier caractère d'opérateur (>, <, =, !). La métrique
  // étant [a-z0-9_]+, le premier caractère d'opérateur rencontré EST l'op.
  p := 0;
  for i := 1 to Length(M) do
    if (M[i] = '>') or (M[i] = '<') or (M[i] = '=') or (M[i] = '!') then
    begin
      p := i;
      Break;
    end;
  if p = 0 then Exit(2);  // pas d'opérateur
  Metric := LowerCase(Trim(Copy(M, 1, p - 1)));
  if (Metric = '') or (not IsValidMetricName(Metric)) then Exit(1);
  // Opérateur : 1 ou 2 caractères (>= <= !=)
  OpS := M[p];
  if (p < Length(M)) and (M[p + 1] = '=') then
  begin
    OpS := OpS + '=';
    Inc(p);
  end;
  case OpS of
    '>':  Op := opGt;
    '>=': Op := opGe;
    '<':  Op := opLt;
    '<=': Op := opLe;
    '=':  Op := opEq;
    '!=': Op := opNe;
    else Exit(3);  // '!' seul, '==' : opérateur inconnu
  end;
  ThrS := Trim(Copy(M, p + 1, Length(M)));
  if not ParseNumber(ThrS, Threshold) then Exit(4);
  // Normalisation : métrique canonique du gate + alias accepté. Le test
  // préalable conserve le nom reçu dans Metric pour le message d'erreur.
  if CanonMetricFailIf(Metric) = '' then Exit(5);
  Metric := CanonMetricFailIf(Metric);
end;

{-----------------------------------------------------------------------------
  ParseDeltaSpec : Parse une SPEC de dérive (--fail-on-delta).
  Grammaire figée : METRIQUE '>' SEUIL — opérateur '>' IMPOSÉ, seuil en %
  décimal. Retour : 0 = OK ; 1 = opérateur '>' manquant ; 2 = métrique
  inconnue (Metric = nom reçu) ; 3 = seuil non numérique ; 4 = métrique
  manquante ; 5 = opérateur '>=' (interdit, '>' seul imposé).
  -----------------------------------------------------------------------------}
function ParseDeltaSpec(const Arg: string; out Metric: string;
                        out Threshold: Double): Integer;
var
  M, ThrS: string;
  p: Integer;
begin
  Result := 0;
  M := Trim(Arg);
  p := Pos('>', M);
  if p = 0 then Exit(1);
  Metric := LowerCase(Trim(Copy(M, 1, p - 1)));
  if Metric = '' then Exit(4);
  if (p < Length(M)) and (M[p + 1] = '=') then Exit(5);  // '>=' : syntaxe imposée '>'
  ThrS := Trim(Copy(M, p + 1, Length(M)));
  if not ParseNumber(ThrS, Threshold) then Exit(3);
  // Normalisation : métrique canonique (clé du summary-json) + alias. Le
  // test préalable conserve le nom reçu dans Metric pour le message d'erreur.
  if CanonMetricDelta(Metric) = '' then Exit(2);
  Metric := CanonMetricDelta(Metric);
end;

{-----------------------------------------------------------------------------
  AppendUTF8 : Ajoute un code point Unicode encodé en UTF-8 à une chaîne
  (déséchappement \uXXXX des chaînes JSON de la baseline).
  -----------------------------------------------------------------------------}
procedure AppendUTF8(var R: string; CP: UInt32);
begin
  if CP < $80 then
    R := R + Chr(CP)
  else if CP < $800 then
    R := R + Chr($C0 or (CP shr 6)) + Chr($80 or (CP and $3F))
  else if CP < $10000 then
    R := R + Chr($E0 or (CP shr 12)) +
             Chr($80 or ((CP shr 6) and $3F)) +
             Chr($80 or (CP and $3F))
  else
    R := R + Chr($F0 or (CP shr 18)) +
             Chr($80 or ((CP shr 12) and $3F)) +
             Chr($80 or ((CP shr 6) and $3F)) +
             Chr($80 or (CP and $3F));
end;

{-----------------------------------------------------------------------------
  JSONUnescape : Déséchappe une chaîne JSON (guillemets retirés par
  l'appelant) : \" \\ \/ \b \f \n \r \t et \uXXXX (encodé en UTF-8).
  -----------------------------------------------------------------------------}
function JSONUnescape(const S: string): string;
var
  i, L, k: Integer;
  CP: UInt32;
begin
  Result := '';
  i := 1;
  L := Length(S);
  while i <= L do
  begin
    if S[i] <> '\' then
    begin
      Result := Result + S[i];
      Inc(i);
    end
    else
    begin
      Inc(i);
      if i > L then Break;
      case S[i] of
        '"': Result := Result + '"';
        '\': Result := Result + '\';
        '/': Result := Result + '/';
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'u':
          begin
            CP := 0;
            for k := 1 to 4 do
            begin
              CP := CP * 16;
              if i + k <= L then
              begin
                case S[i + k] of
                  '0'..'9': CP := CP + (Ord(S[i + k]) - 48);
                  'a'..'f': CP := CP + (Ord(S[i + k]) - 87);
                  'A'..'F': CP := CP + (Ord(S[i + k]) - 55);
                end;
              end;
            end;
            AppendUTF8(Result, CP);
            Inc(i, 4);
          end;
        else Result := Result + S[i];  // échappement inconnu : conservé tel quel
      end;
      Inc(i);
    end;
  end;
end;

{-----------------------------------------------------------------------------
  ParseJSONObject : Parse un objet JSON en paires clé/valeur de premier
  niveau (les objets/tableaux imbriqués sont sautés de manière équilibrée et
  ignorés). Les chaînes sont déséchappées (JSONUnescape). Structure minimale
  "clé" : valeur, ... ; en cas de malformation, l'objet partiel est renvoyé
  (l'appelant vérifie la clé "file").
  -----------------------------------------------------------------------------}
procedure ParseJSONObject(const S: string; var Keys, Values: TStringArray);
var
  i, L: Integer;
  K, V: string;

  procedure SkipWS;
  begin
    while (i <= L) and (S[i] in [#9, #10, #13, #32]) do Inc(i);
  end;

  // Lit la chaîne brute entre guillemets (échappements inclus), puis la
  // déséchappe (JSONUnescape) — les octets UTF-8 passent tels quels.
  function ReadString: string;
  begin
    Result := '';
    Inc(i);  // guillemet ouvrant
    while i <= L do
    begin
      if S[i] = '"' then
      begin
        Inc(i);
        Result := JSONUnescape(Result);
        Exit;
      end;
      Result := Result + S[i];
      Inc(i);
    end;
    Result := JSONUnescape(Result);
  end;

  // Saute une valeur imbriquée (objet/tableau) en respectant les chaînes
  procedure SkipNested(OpenC, CloseC: Char);
  var
    D: Integer;
    InS: Boolean;
  begin
    D := 1;
    InS := False;
    Inc(i);  // caractère ouvrant
    while (i <= L) and (D > 0) do
    begin
      if InS then
      begin
        if S[i] = '\' then Inc(i)
        else if S[i] = '"' then InS := False;
      end
      else
      begin
        if S[i] = '"' then InS := True
        else if S[i] = OpenC then Inc(D)
        else if S[i] = CloseC then Dec(D);
      end;
      Inc(i);
    end;
  end;

  // Lit une valeur scalaire (nombre, true/false/null) : s'arrête sur , } ]
  function ReadScalar: string;
  begin
    Result := '';
    while (i <= L) and (S[i] <> ',') and (S[i] <> '}') and (S[i] <> ']') do
    begin
      if not (S[i] in [#9, #10, #13, #32]) then Result := Result + S[i];
      Inc(i);
    end;
  end;

begin
  SetLength(Keys, 0);
  SetLength(Values, 0);
  i := 1;
  L := Length(S);
  SkipWS;
  if (i > L) or (S[i] <> '{') then Exit;
  Inc(i);
  while True do
  begin
    SkipWS;
    if i > L then Break;
    if S[i] = '}' then
    begin
      Inc(i);
      Break;
    end;
    if S[i] <> '"' then Break;  // clé non-chaîne : objet malformé, on s'arrête
    K := ReadString;
    SkipWS;
    if (i > L) or (S[i] <> ':') then Break;
    Inc(i);
    SkipWS;
    if i > L then Break;
    if S[i] = '"' then V := ReadString
    else if S[i] = '{' then
    begin
      SkipNested('{', '}');
      V := '';
    end
    else if S[i] = '[' then
    begin
      SkipNested('[', ']');
      V := '';
    end
    else
      V := ReadScalar;
    SetLength(Keys, Length(Keys) + 1);
    Keys[High(Keys)] := K;
    SetLength(Values, Length(Values) + 1);
    Values[High(Values)] := V;
    SkipWS;
    if (i <= L) and (S[i] = ',') then
    begin
      Inc(i);
      Continue;
    end;
    if (i <= L) and (S[i] = '}') then
    begin
      Inc(i);
      Break;
    end;
    Break;
  end;
end;

{-----------------------------------------------------------------------------
  SplitJSONObjects : Découpe un flux JSON en objets de premier niveau
  (NDJSON : un objet par ligne, ou un objet unique multi-lignes). Les blancs
  entre les objets sont ignorés ; tout autre contenu hors objet -> False
  (baseline invalide). Retourne False aussi si une accolade n'est pas fermée.
  -----------------------------------------------------------------------------}
function SplitJSONObjects(const S: string; var Objs: TStringArray): Boolean;
var
  i, L, Depth, Start: Integer;
  InStr: Boolean;
begin
  Result := True;
  SetLength(Objs, 0);
  i := 1;
  L := Length(S);
  Depth := 0;
  Start := 0;
  InStr := False;
  while i <= L do
  begin
    if InStr then
    begin
      if S[i] = '\' then Inc(i)   // échappement : saute le caractère suivant
      else if S[i] = '"' then InStr := False;
    end
    else
    begin
      case S[i] of
        '"': InStr := True;
        '{':
          begin
            if Depth = 0 then Start := i;
            Inc(Depth);
          end;
        '}':
          begin
            Dec(Depth);
            if Depth = 0 then
            begin
              SetLength(Objs, Length(Objs) + 1);
              Objs[High(Objs)] := Copy(S, Start, i - Start + 1);
            end;
          end;
        #9, #10, #13, #32: ;  // blancs entre objets : ignorés
        else
          if Depth = 0 then Exit(False);  // contenu non JSON hors objet
      end;
    end;
    Inc(i);
  end;
  if Depth <> 0 then Exit(False);  // accolade non fermée
end;

{-----------------------------------------------------------------------------
  BaselineValue : Valeur numérique d'une clé d'entrée baseline (true/false
  pour bom -> 1/0). Retourne False si la clé est absente ou non numérique.
  -----------------------------------------------------------------------------}
function BaselineValue(const E: TBaselineEntry; const Key: string;
                       out V: Double): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(E.Keys) do
    if E.Keys[i] = Key then
    begin
      if E.Values[i] = 'true' then
      begin
        V := 1;
        Result := True;
      end
      else if E.Values[i] = 'false' then
      begin
        V := 0;
        Result := True;
      end
      else
        Result := ParseNumber(E.Values[i], V);
      Exit;
    end;
end;

{-----------------------------------------------------------------------------
  LoadBaseline : Lit et parse un fichier baseline (NDJSON produit par
  --summary-json ; un objet unique est accepté). Chaque objet doit avoir la
  clé "file", sinon erreur fatale exit 1 (message stderr français).
  -----------------------------------------------------------------------------}
procedure LoadBaseline(const Path: string; var Baseline: TBaselineArray);
var
  FS: TFileStream;
  S: string;
  Objs: TStringArray;
  i, j: Integer;
  Keys, Values: TStringArray;
begin
  SetLength(Baseline, 0);
  try
    FS := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, 'Erreur: baseline introuvable ou illisible - ', Path);
      Halt(1);
    end;
  end;
  try
    SetLength(S, LongInt(FS.Size));
    if FS.Size > 0 then
      FS.Read(S[1], LongInt(FS.Size));
  finally
    FS.Free;
  end;
  if not SplitJSONObjects(S, Objs) then
  begin
    WriteLn(ErrOutput, 'Erreur: baseline invalide - ', Path,
            ' (contenu non JSON ou accolades non fermées)');
    Halt(1);
  end;
  if Length(Objs) = 0 then
  begin
    WriteLn(ErrOutput, 'Erreur: baseline invalide - ', Path,
            ' (aucun objet JSON trouvé)');
    Halt(1);
  end;
  SetLength(Baseline, Length(Objs));
  for i := 0 to High(Objs) do
  begin
    ParseJSONObject(Objs[i], Keys, Values);
    j := 0;
    while (j < Length(Keys)) and (Keys[j] <> 'file') do Inc(j);
    if j >= Length(Keys) then
    begin
      WriteLn(ErrOutput, 'Erreur: baseline invalide - ', Path,
              ' (objet ', i + 1, ' : clé "file" manquante)');
      Halt(1);
    end;
    Baseline[i].FilePath := Values[j];
    Baseline[i].Keys := Keys;
    Baseline[i].Values := Values;
  end;
end;

{-----------------------------------------------------------------------------
  EvaluateChecks : Évalue tous les checks définis sur un fichier (après
  l'analyse, sur les compteurs TStats — le streaming et la mémoire bornée ne
  sont pas affectés). Les checks delta sont ignorés si le fichier n'a pas
  d'entrée baseline correspondante (comparaison exacte de "file", documenté)
  ou si la clé de la métrique est absente de l'entrée. Ids : 'metric',
  'metric#2', ... pour les répétitions ; 'delta:metric', 'delta:metric#2', ...
  pour les checks de dérive.
  -----------------------------------------------------------------------------}
procedure EvaluateChecks(const Stats: TStats; const Checks: TCheckArray;
                         const Baseline: TBaselineArray;
                         out Results: TCheckResultArray);
var
  i, j, Entry, Ordinal: Integer;
  V, Base, Delta: Double;
  Key: string;
  R: TCheckResult;
begin
  SetLength(Results, 0);
  // Entrée baseline de ce fichier : comparaison EXACTE de la chaîne "file"
  Entry := -1;
  for j := 0 to High(Baseline) do
    if Baseline[j].FilePath = Stats.Path then
    begin
      Entry := j;
      Break;
    end;
  for i := 0 to High(Checks) do
  begin
    if Checks[i].IsDelta then
    begin
      // Check de dérive : sans baseline (fichier ou clé absente), il est
      // ignoré pour ce fichier (pas d'erreur — comportement documenté).
      if Entry < 0 then Continue;
      if not BaselineValue(Baseline[Entry], Checks[i].Metric, Base) then Continue;
      if not CheckMetricValue(Stats, Checks[i].Metric, V) then Continue;
      if Base = 0 then
      begin
        if V = 0 then
        begin
          Delta := 0;
          R.DeltaInf := False;
        end
        else
        begin
          // Documenté : une métrique qui passe de 0 à >0 est une dérive
          // infinie — le check échoue quel que soit le seuil.
          Delta := 0;
          R.DeltaInf := True;
        end;
      end
      else
      begin
        Delta := (V - Base) / Base * 100;
        R.DeltaInf := False;
      end;
      R.Actual := Delta;   // pour un delta, la valeur comparée EST le delta %
      R.Metric := Checks[i].Metric;
      R.Op := opGt;
      R.Threshold := Checks[i].Threshold;
      R.IsDelta := True;
      if R.DeltaInf or (Delta > Checks[i].Threshold) then
        R.Status := csFail
      else
        R.Status := csOk;
    end
    else
    begin
      if not CheckMetricValue(Stats, Checks[i].Metric, V) then Continue;
      R.Actual := V;
      R.Metric := Checks[i].Metric;
      R.Op := Checks[i].Op;
      R.Threshold := Checks[i].Threshold;
      R.IsDelta := False;
      R.DeltaInf := False;
      // --warn-if : condition vraie -> warn (non bloquant) ; --fail-if -> fail
      if EvalCompare(V, Checks[i].Op, Checks[i].Threshold) then
      begin
        if Checks[i].IsWarn then R.Status := csWarn
        else R.Status := csFail;
      end
      else
        R.Status := csOk;
    end;
    // Id : 'metric' (ou 'delta:metric'), puis '#2', '#3'... pour les répétitions
    if R.IsDelta then Key := 'delta:' + R.Metric
    else Key := R.Metric;
    Ordinal := 1;
    for j := 0 to High(Results) do
      if (Results[j].IsDelta = R.IsDelta) and (Results[j].Metric = R.Metric) then
        Inc(Ordinal);
    if Ordinal = 1 then R.Id := Key
    else R.Id := Key + '#' + IntToStr(Ordinal);
    SetLength(Results, Length(Results) + 1);
    Results[High(Results)] := R;
  end;
end;

{-----------------------------------------------------------------------------
  Affichage console — style CLI épuré (ASCII pur, sans bordures Unicode)
  -----------------------------------------------------------------------------
  Règles :
  - Aucun caractère de boîte Unicode (═ ║ ┌ …), aucun code ANSI par défaut :
    colonnes alignées avec des espaces, soulignés de section en tirets ASCII.
  - Le bloc Summary est toujours affiché ; les sections Top Characters /
    Top Words / Longest Lines sont filtrées par --char / --word / --line.
  - Le suffixe "(N of K)" n'apparaît que si K (total réel) dépasse la limite
    affichée (10 par défaut, ou tout avec --all).
  - Coloriage minimal des titres de section : uniquement via --color et quand
    la sortie est réellement une console (NoColor reste True sinon).
  -----------------------------------------------------------------------------}

{-----------------------------------------------------------------------------
  SummaryLine : Formate une ligne du bloc Summary
  Entrée  : Label_ - Libellé (ex. 'Lines:'), Value - Valeur numérique
  Sortie  : "  <Label_>...<valeur>" avec la valeur alignée à droite
            (bord droit au même endroit, colonne 24)
  -----------------------------------------------------------------------------}
function SummaryLine(const Label_: string; Value: Int64): string;
var
  S: string;
  Pad: Integer;
begin
  S := IntToStr(Value);
  Pad := 22 - Length(Label_) - Length(S);
  if Pad < 0 then Pad := 0;  // Valeurs très longues : pas de coupure
  Result := '  ' + Label_ + StringOfChar(' ', Pad) + S;
end;

{-----------------------------------------------------------------------------
  SummaryLineText : Comme SummaryLine, mais pour une valeur texte (ex. BOM).
  -----------------------------------------------------------------------------}
function SummaryLineText(const Label_: string; const Value: string): string;
var
  Pad: Integer;
begin
  Pad := 22 - Length(Label_) - Length(Value);
  if Pad < 0 then Pad := 0;
  Result := '  ' + Label_ + StringOfChar(' ', Pad) + Value;
end;

{-----------------------------------------------------------------------------
  SectionTitle : Construit le titre d'une section avec suffixe "(N of K)"
  Entrée  : Name - Nom de la section, Limit - Limite affichée, Total - Total réel
  Sortie  : "Name" ou "Name (Limit of Total)" si Limit < Total
  -----------------------------------------------------------------------------}
function SectionTitle(const Name: string; Limit, Total: Integer): string;
begin
  Result := Name;
  if Limit < Total then
    Result := Name + ' (' + IntToStr(Limit) + ' of ' + IntToStr(Total) + ')';
end;

procedure PrintStats(const Stats: TStats; ShowChars, ShowWords, ShowLines, ShowAll: Boolean;
                     LexicalStats: Boolean; Readability: Boolean;
                     TopWordsLimit, TopCharsLimit: Integer;
                     const CheckResults: TCheckResultArray);
var
  i, Limit, Total, RankW: Integer;
  Title, Preview: string;
  Lx: TLexicalStats;
  Rd: TReadabilityStats;
begin
  { En-tête : chemin du fichier et horodatage de génération (traçabilité) }
  WriteLn('File: ', Stats.Path);
  WriteLn('Generated: ', CurrentStamp);
  WriteLn;

  { Section Summary — toujours affichée }
  Title := 'Summary';
  WriteLn(AnsiColor(36), Title, AnsiReset);   // 36 = cyan (titres de section)
  WriteLn(RepeatString('-', Length(Title)));
  WriteLn(SummaryLine('Lines:', Stats.LineCount));
  WriteLn(SummaryLine('Words:', Stats.WordCount));
  WriteLn(SummaryLine('Characters:', Stats.CharCount));
  WriteLn(SummaryLine('Sentences:', Stats.SentenceCount));
  WriteLn(SummaryLine('Avg words/sentence:', Stats.AvgWordsPerSentence));
  WriteLn(Format('  Line length:  min %d, max %d, avg %d',
        [Stats.MinLen, Stats.MaxLen, Stats.AvgLen]));
  WriteLn;

  { Section Checks (Cible 1, v2.6.0) — affichée uniquement en mode check avec
    au moins un check évalué sur ce fichier. Insérée après Summary : le
    résultat du gate d'abord visible. Format (ASCII pur) :
      <metric> <op> <seuil> : <STATUS> (actual <valeur>)
      delta <metric> > <seuil>% : <STATUS> (delta <delta>%) }
  if Length(CheckResults) > 0 then
  begin
    Title := 'Checks';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    for i := 0 to High(CheckResults) do
    begin
      if CheckResults[i].IsDelta then
      begin
        if CheckResults[i].DeltaInf then
          WriteLn('  delta ', CheckResults[i].Metric, ' ', OpToStr(CheckResults[i].Op), ' ',
                  FormatFloatTrim(CheckResults[i].Threshold, 4), '% : ',
                  CheckStatusStr(CheckResults[i].Status, True), ' (delta inf%)')
        else
          WriteLn('  delta ', CheckResults[i].Metric, ' ', OpToStr(CheckResults[i].Op), ' ',
                  FormatFloatTrim(CheckResults[i].Threshold, 4), '% : ',
                  CheckStatusStr(CheckResults[i].Status, True), ' (delta ',
                  FormatFloatTrimSigned(CheckResults[i].Actual, 4), '%)')
      end
      else
        WriteLn('  ', CheckResults[i].Metric, ' ', OpToStr(CheckResults[i].Op), ' ',
                FormatFloatTrim(CheckResults[i].Threshold, 4), ' : ',
                CheckStatusStr(CheckResults[i].Status, True), ' (actual ',
                FormatFloatTrim(CheckResults[i].Actual, 4), ')');
    end;
    WriteLn;
  end;

  { Section Lexical — affichée uniquement avec --lexical-stats (C2-A).
    Métriques calculées à la volée depuis les fréquences du mode courant. }
  if LexicalStats then
  begin
    Lx := ComputeLexical(Stats);
    Title := 'Lexical';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn(SummaryLine('Unique words:', Lx.UniqueWords));
    WriteLn(SummaryLine('Hapax:', Lx.Hapax));
    WriteLn(SummaryLineText('Type-token ratio:', FormatFloatTrim(Lx.TypeTokenRatio, 4)));
    WriteLn(SummaryLineText('Avg word length:', FormatFloatTrim(Lx.AverageWordLength, 4)));
    WriteLn(SummaryLineText('Entropy:', FormatFloatTrim(Lx.EntropyBitsPerWord, 4)));
    WriteLn;
  end;

  { Section Readability — affichée uniquement avec --readability (C2-C).
    Style et alignement identiques à la section Lexical ; valeurs formatées
    avec FormatFloatTrim(v, 4) comme les métriques lexicales console. }
  if Readability then
  begin
    Rd := ComputeReadability(Stats);
    Title := 'Readability';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn(SummaryLineText('Avg sentence words:', FormatFloatTrim(Rd.AvgSentenceWords, 4)));
    WriteLn(SummaryLineText('Avg word chars:', FormatFloatTrim(Rd.AvgWordChars, 4)));
    WriteLn(SummaryLineText('Pct long words:', FormatFloatTrim(Rd.PctLongWords, 4) + '%'));
    WriteLn(SummaryLineText('Score (0-100):', FormatFloatTrim(Rd.Score, 4)));
    WriteLn;
  end;

  { Section Quality — affichée uniquement si au moins un compteur qualité est
    non nul (ou BOM présent) : la sortie reste identique pour les fichiers
    « propres », rétrocompatibilité totale. }
  if (Stats.InvalidUTF8 > 0) or Stats.BOM or (Stats.CRLF > 0) or
     (Stats.Tabs > 0) or (Stats.NonPrintable > 0) then
  begin
    Title := 'Quality';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn(SummaryLine('Invalid UTF-8:', Stats.InvalidUTF8));
    if Stats.BOM then
      WriteLn(SummaryLineText('BOM:', 'yes'))
    else
      WriteLn(SummaryLineText('BOM:', 'no'));
    WriteLn(SummaryLine('CRLF:', Stats.CRLF));
    WriteLn(SummaryLine('Tabs:', Stats.Tabs));
    WriteLn(SummaryLine('Non-printable:', Stats.NonPrintable));
    WriteLn;
  end;

  { Section Top Characters }
  if ShowChars and (Length(Stats.Freq) > 0) then
  begin
    Total := Length(Stats.Freq);
    Limit := EffectiveLimit(Total, ShowAll, TopCharsLimit);
    RankW := Length(IntToStr(Limit));
    if RankW < 2 then RankW := 2;

    Title := SectionTitle('Top Characters', Limit, Total);
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn('  ', StringOfChar(' ', RankW - 1), '#', '  ',
            UTF8PadRight('Char', 8), '  ',
            UTF8PadRight('Code', 8), '  ',
            StringOfChar(' ', 3), 'Count');

    for i := 0 to Limit - 1 do
      WriteLn('  ', i + 1:RankW, '  ',
              UTF8PadRight(QuotedStr(VisualChar(Stats.Freq[i].CodePoint)), 8), '  ',
              UTF8PadRight(UnicodeCode(Stats.Freq[i].CodePoint), 8), '  ',
              Format('%8d', [Stats.Freq[i].Count]));
    WriteLn;
  end;

  { Section Top Words }
  if ShowWords and (Length(Stats.Words) > 0) then
  begin
    Total := Length(Stats.Words);
    Limit := EffectiveLimit(Total, ShowAll, TopWordsLimit);
    RankW := Length(IntToStr(Limit));
    if RankW < 2 then RankW := 2;

    Title := SectionTitle('Top Words', Limit, Total);
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn('  ', StringOfChar(' ', RankW - 1), '#', '  ',
            UTF8PadRight('Word', 16), '  ',
            StringOfChar(' ', 3), 'Count');

    for i := 0 to Limit - 1 do
    begin
      Preview := QuotedStr(Stats.Words[i].Word);
      { Tronque les mots très longs pour préserver l'alignement des colonnes }
      if UTF8Length(Preview) > 32 then
        Preview := UTF8SafeCopy(Preview, 29) + '...';
      WriteLn('  ', i + 1:RankW, '  ',
              UTF8PadRight(Preview, 16), '  ',
              Format('%8d', [Stats.Words[i].Count]));
    end;
    WriteLn;
  end;

  { Section N-grams (C2-B) — affichée uniquement avec --ngrams=N. Rang,
    n-gram (mots séparés par un espace) et compte. Pas de suffixe "(N of K)" :
    le dictionnaire est borné au top-K, le total réel n'est pas connu. }
  if Stats.NGramSize > 0 then
  begin
    Total := Length(Stats.NGrams);
    Limit := EffectiveLimit(Total, ShowAll, TopNgramsLimit);
    RankW := Length(IntToStr(Limit));
    if RankW < 2 then RankW := 2;

    Title := 'N-grams (N=' + IntToStr(Stats.NGramSize) + ')';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn('  ', StringOfChar(' ', RankW - 1), '#', '  ',
            UTF8PadRight('N-gram', 24), '  ',
            StringOfChar(' ', 3), 'Count');

    for i := 0 to Limit - 1 do
    begin
      Preview := JoinNGramWords(Stats.NGrams[i].Words);
      if UTF8Length(Preview) > 40 then
        Preview := UTF8SafeCopy(Preview, 37) + '...';
      WriteLn('  ', i + 1:RankW, '  ',
              UTF8PadRight(Preview, 24), '  ',
              Format('%8d', [Stats.NGrams[i].Count]));
    end;
    WriteLn;
  end;

  { Section Histogram (C2-B) — affichée uniquement avec --histogram=...
    Barres en ASCII pur (1 '#' par occurrence, plafonnées à 60) + compte
    numérique. Classes identiques aux exemples de la roadmap §6.6 pour
    line_length ; classes stables documentées pour les deux autres. }
  if Stats.HistogramKind <> hkNone then
  begin
    Title := 'Histogram (' + HistogramName(Stats.HistogramKind) + ')';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    for i := 0 to High(Stats.HistCounts) do
      WriteLn('  ', UTF8PadRight(Stats.HistRanges[i], 5), '  ',
              RepeatString('#', Integer(MinInt64(Stats.HistCounts[i], 60))), ' ',
              Stats.HistCounts[i]);
    WriteLn;
  end;

  { Section Character Classes (C2-B) — affichée uniquement avec --char-classes.
    La somme des six classes = characters (assertion de test). }
  if Stats.CharClassesEnabled then
  begin
    Title := 'Character Classes';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn(SummaryLine('Letters:', Stats.CharClasses[CC_LETTERS]));
    WriteLn(SummaryLine('Digits:', Stats.CharClasses[CC_DIGITS]));
    WriteLn(SummaryLine('Whitespace:', Stats.CharClasses[CC_WHITESPACE]));
    WriteLn(SummaryLine('Punctuation:', Stats.CharClasses[CC_PUNCTUATION]));
    WriteLn(SummaryLine('Control:', Stats.CharClasses[CC_CONTROL]));
    WriteLn(SummaryLine('Other:', Stats.CharClasses[CC_OTHER]));
    WriteLn;
  end;

  { Section Longest Lines }
  if ShowLines and (Length(Stats.TopLines) > 0) then
  begin
    { K (total réel) = nombre de lignes du fichier : AddLine ne mémorise que
      les N plus longues en mode Top N, on ne peut donc pas utiliser la taille
      du tableau TopLines comme total réel. }
    Total := Stats.LineCount;
    Limit := Total;
    if (not ShowAll) and (Limit > DEFAULT_TOP_LIMIT) then
      Limit := DEFAULT_TOP_LIMIT;
    RankW := Length(IntToStr(Limit));
    if RankW < 2 then RankW := 2;

    Title := SectionTitle('Longest Lines', Limit, Total);
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn('  ', StringOfChar(' ', RankW - 1), '#', '  ',
            UTF8PadRight('Length', 6), '  Preview');

    { Le tableau TopLines peut contenir moins de lignes que LineCount
      (lignes vides exclues par AddLine) : borne supérieure de sécurité }
    if Limit > Length(Stats.TopLines) then
      Limit := Length(Stats.TopLines);

    for i := 0 to Limit - 1 do
    begin
      Preview := Stats.TopLines[i].Text;
      { Préview tronquée à ~60 caractères UTF-8 sans couper une séquence
        multi-octets (UTF8SafeCopy), suffixée de "..." si tronquée }
      if UTF8Length(Preview) > 60 then
        Preview := UTF8SafeCopy(Preview, 57) + '...';
      WriteLn('  ', i + 1:RankW, '  ',
              Format('%6d', [Stats.TopLines[i].Len]), '  ',
              Preview);
    end;
    WriteLn;
  end;
end;

{=============================================================================
  EXPORT JSON - FORMATAGE SÉCURISÉ
  =============================================================================
  Objectif : Générer un JSON valide avec échappement strict des caractères
  Sécurité : 
    - Échappe tous les caractères de contrôle (\n, \t, etc.) en séquences \uXXXX
    - Échappe les guillemets et backslashes pour éviter l'injection JSON
    - Garantit que chaque entrée tient sur une ligne (pas de vrais sauts de ligne)
  =============================================================================}
{-----------------------------------------------------------------------------
  JsonEscape — CORRECTION : codes numériques #N au lieu de littéraux Char
-----------------------------------------------------------------------------}
function JsonEscape(const S: string): string;
var
  i: Integer;
  C: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    case Ord(C) of
      34: Result := Result + '\"';   { #34 = guillemet double }
      92: Result := Result + '\\';   { #92 = backslash }
      47: Result := Result + '\/';   { #47 = slash }
      8:  Result := Result + '\b';   { #8  = backspace }
      9:  Result := Result + '\t';   { #9  = tab }
      10: Result := Result + '\n';   { #10 = LF }
      12: Result := Result + '\f';   { #12 = form feed }
      13: Result := Result + '\r';   { #13 = CR }
      else
        if Ord(C) < 32 then
          Result := Result + '\u' + HexStr(Ord(C), 4)
        else
          Result := Result + C;
    end;
  end;
end;

procedure ExportJSON(const Stats: TStats; ShowAll: Boolean; LexicalStats: Boolean;
                    Readability: Boolean; const CheckResults: TCheckResultArray);
var
  i, j, Limit: Integer;
  Lx: TLexicalStats;
  Rd: TReadabilityStats;
begin
  WriteLn('{');
  WriteLn('  "file": "', JsonEscape(Stats.Path), '",');
  WriteLn('  "generated": "', JsonEscape(CurrentStamp), '",');
  WriteLn('  "tool": "fstats",');
  WriteLn('  "version": "', FSTATS_VERSION, '",');
  WriteLn('  "schema_version": "1.0",');
  WriteLn('  "statistics": {');
  WriteLn('    "lines": ', Stats.LineCount, ',');
  WriteLn('    "words": ', Stats.WordCount, ',');
  WriteLn('    "characters": ', Stats.CharCount, ',');
  WriteLn('    "sentences": ', Stats.SentenceCount, ',');
  WriteLn('    "avg_words_per_sentence": ', Stats.AvgWordsPerSentence, ',');
  WriteLn('    "line_lengths": {');
  WriteLn('      "min": ', Stats.MinLen, ',');
  WriteLn('      "max": ', Stats.MaxLen, ',');
  WriteLn('      "average": ', Stats.AvgLen);
  WriteLn('    }');
  WriteLn('  },');
  WriteLn('  "quality": {');
  WriteLn('    "invalid_utf8": ', Stats.InvalidUTF8, ',');
  if Stats.BOM then
    WriteLn('    "bom": true,')
  else
    WriteLn('    "bom": false,');
  WriteLn('    "crlf": ', Stats.CRLF, ',');
  WriteLn('    "tabs": ', Stats.Tabs, ',');
  WriteLn('    "nonprintable": ', Stats.NonPrintable);
  WriteLn('  },');

  // Checks (Cible 1, v2.6.0) : bloc additif inséré après "quality", avant
  // les blocs additifs (char_classes, histogram, ngrams, lexical, readability).
  // Absent avec --summary-json et --csv (documenté) ; présent par fichier
  // dans --json-mode=aggregate (jamais dans "totals").
  if Length(CheckResults) > 0 then
  begin
    WriteLn('  "checks": [');
    for i := 0 to High(CheckResults) do
    begin
      if i > 0 then WriteLn(',');
      if CheckResults[i].DeltaInf then
        Write('    {"id": "', JsonEscape(CheckResults[i].Id), '", "metric": "',
              JsonEscape(CheckResults[i].Metric), '", "actual": 1e300')
      else
        Write('    {"id": "', JsonEscape(CheckResults[i].Id), '", "metric": "',
              JsonEscape(CheckResults[i].Metric), '", "actual": ',
              FormatFloatTrimSigned(CheckResults[i].Actual, 4));
      Write(', "op": "', OpToStr(CheckResults[i].Op), '"');
      Write(', "threshold": ', FormatFloatTrim(CheckResults[i].Threshold, 4));
      Write(', "status": "', CheckStatusStr(CheckResults[i].Status, False), '"}');
    end;
    WriteLn;
    WriteLn('  ],');
  end;

  // Structure (C2-B) : classes de caractères, histogramme et n-grams — clés
  // additionnelles (ajout additif, les clés existantes sont inchangées)
  if Stats.CharClassesEnabled then
  begin
    WriteLn('  "char_classes": {');
    WriteLn('    "letters": ', Stats.CharClasses[CC_LETTERS], ',');
    WriteLn('    "digits": ', Stats.CharClasses[CC_DIGITS], ',');
    WriteLn('    "whitespace": ', Stats.CharClasses[CC_WHITESPACE], ',');
    WriteLn('    "punctuation": ', Stats.CharClasses[CC_PUNCTUATION], ',');
    WriteLn('    "control": ', Stats.CharClasses[CC_CONTROL], ',');
    WriteLn('    "other": ', Stats.CharClasses[CC_OTHER]);
    WriteLn('  },');
  end;

  if Stats.HistogramKind <> hkNone then
  begin
    WriteLn('  "histogram": {');
    WriteLn('    "metric": "', HistogramName(Stats.HistogramKind), '",');
    WriteLn('    "classes": [');
    for i := 0 to High(Stats.HistCounts) do
    begin
      if i > 0 then WriteLn(',');
      Write('      {"range": "', Stats.HistRanges[i], '", "count": ',
            Stats.HistCounts[i], '}');
    end;
    WriteLn;
    WriteLn('    ]');
    WriteLn('  },');
  end;

  if Stats.NGramSize > 0 then
  begin
    Write('  "ngrams": [');
    Limit := EffectiveLimit(Length(Stats.NGrams), ShowAll, TopNgramsLimit) - 1;
    for i := 0 to Limit do
    begin
      if i > 0 then Write(',');
      WriteLn;
      Write('    {"rank": ', i + 1, ', ');
      Write('"words": [');
      for j := 0 to High(Stats.NGrams[i].Words) do
      begin
        if j > 0 then Write(', ');
        Write('"', JsonEscape(Stats.NGrams[i].Words[j]), '"');
      end;
      Write('], "count": ', Stats.NGrams[i].Count, '}');
    end;
    WriteLn;
    WriteLn('  ],');
  end;

  // Statistiques lexicales (--lexical-stats) : clés additionnelles — ajout
  // additif, les clés existantes sont inchangées
  if LexicalStats then
  begin
    Lx := ComputeLexical(Stats);
    WriteLn('  "lexical": {');
    WriteLn('    "unique_words": ', Lx.UniqueWords, ',');
    WriteLn('    "hapax": ', Lx.Hapax, ',');
    WriteLn('    "type_token_ratio": ', FormatFloatTrim(Lx.TypeTokenRatio, 6), ',');
    WriteLn('    "average_word_length": ', FormatFloatTrim(Lx.AverageWordLength, 6), ',');
    WriteLn('    "entropy_bits_per_word": ', FormatFloatTrim(Lx.EntropyBitsPerWord, 6));
    WriteLn('  },');
  end;

  // Lisibilité (--readability, C2-C) : bloc additif, inséré après le bloc
  // lexical (ou après "quality" si --lexical-stats est absent). FormatFloatTrim
  // à 6 décimales comme le bloc lexical.
  if Readability then
  begin
    Rd := ComputeReadability(Stats);
    WriteLn('  "readability": {');
    WriteLn('    "avg_sentence_words": ', FormatFloatTrim(Rd.AvgSentenceWords, 6), ',');
    WriteLn('    "avg_word_chars": ', FormatFloatTrim(Rd.AvgWordChars, 6), ',');
    WriteLn('    "pct_long_words": ', FormatFloatTrim(Rd.PctLongWords, 6), ',');
    WriteLn('    "score": ', FormatFloatTrim(Rd.Score, 6));
    WriteLn('  },');
  end;

  // Top Characters
  Write('  "top_characters": [');
  Limit := EffectiveLimit(Length(Stats.Freq), ShowAll, TopCharsLimit) - 1;
  for i := 0 to Limit do
  begin
    if i > 0 then Write(',');
    WriteLn;
    Write('    {"rank": ', i+1, ', ');
    Write('"character": "', JsonEscape(VisualChar(Stats.Freq[i].CodePoint)), '", ');
    Write('"code_point": "', UnicodeCode(Stats.Freq[i].CodePoint), '", ');
    Write('"count": ', Stats.Freq[i].Count, '}');
  end;
  WriteLn;
  WriteLn('  ],');

  // Top Words
  Write('  "top_words": [');
  Limit := EffectiveLimit(Length(Stats.Words), ShowAll, TopWordsLimit) - 1;
  for i := 0 to Limit do
  begin
    if i > 0 then Write(',');
    WriteLn;
    Write('    {"rank": ', i+1, ', ');
    Write('"word": "', JsonEscape(Stats.Words[i].Word), '", ');
    Write('"count": ', Stats.Words[i].Count, '}');
  end;
  WriteLn;
  WriteLn('  ],');

  // Longest Lines
  Write('  "longest_lines": [');
  Limit := EffectiveLimit(Length(Stats.TopLines), ShowAll, DEFAULT_TOP_LIMIT) - 1;
  for i := 0 to Limit do
  begin
    if i > 0 then Write(',');
    WriteLn;
    Write('    {"rank": ', i+1, ', ');
    Write('"length": ', Stats.TopLines[i].Len, ', ');
    Write('"content": "', JsonEscape(Stats.TopLines[i].Text), '"}');
  end;
  WriteLn;
  WriteLn('  ]');
  WriteLn('}');
end;

{-----------------------------------------------------------------------------
  BoolToJSON : Convertit un booléen en littéral JSON (true/false minuscules).
  -----------------------------------------------------------------------------}
function BoolToJSON(B: Boolean): string;
begin
  if B then Result := 'true' else Result := 'false';
end;

{-----------------------------------------------------------------------------
  BuildTopCharsJSON : Tableau JSON compact des caractères les plus fréquents
  (une seule ligne, pour NDJSON / array / aggregate).
  -----------------------------------------------------------------------------}
function BuildTopCharsJSON(const Stats: TStats; ShowAll: Boolean; TopLimit: Integer): string;
var
  i, Limit: Integer;
begin
  Limit := EffectiveLimit(Length(Stats.Freq), ShowAll, TopLimit) - 1;
  Result := '[';
  for i := 0 to Limit do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '{"rank": ' + IntToStr(i + 1) +
      ', "character": "' + JsonEscape(VisualChar(Stats.Freq[i].CodePoint)) + '"' +
      ', "code_point": "' + UnicodeCode(Stats.Freq[i].CodePoint) + '"' +
      ', "count": ' + IntToStr(Stats.Freq[i].Count) + '}';
  end;
  Result := Result + ']';
end;

{-----------------------------------------------------------------------------
  BuildTopWordsJSON : Tableau JSON compact des mots les plus fréquents.
  -----------------------------------------------------------------------------}
function BuildTopWordsJSON(const Stats: TStats; ShowAll: Boolean; TopLimit: Integer): string;
var
  i, Limit: Integer;
begin
  Limit := EffectiveLimit(Length(Stats.Words), ShowAll, TopLimit) - 1;
  Result := '[';
  for i := 0 to Limit do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '{"rank": ' + IntToStr(i + 1) +
      ', "word": "' + JsonEscape(Stats.Words[i].Word) + '"' +
      ', "count": ' + IntToStr(Stats.Words[i].Count) + '}';
  end;
  Result := Result + ']';
end;

{-----------------------------------------------------------------------------
  BuildTopLinesJSON : Tableau JSON compact des lignes les plus longues.
  -----------------------------------------------------------------------------}
function BuildTopLinesJSON(const Stats: TStats; ShowAll: Boolean): string;
var
  i, Limit: Integer;
begin
  Limit := EffectiveLimit(Length(Stats.TopLines), ShowAll, DEFAULT_TOP_LIMIT) - 1;
  Result := '[';
  for i := 0 to Limit do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '{"rank": ' + IntToStr(i + 1) +
      ', "length": ' + IntToStr(Stats.TopLines[i].Len) +
      ', "content": "' + JsonEscape(Stats.TopLines[i].Text) + '"}';
  end;
  Result := Result + ']';
end;

{-----------------------------------------------------------------------------
  BuildHistogramJSON : Objet JSON compact de l'histogramme (--histogram, C2-B).
  -----------------------------------------------------------------------------}
function BuildHistogramJSON(const Stats: TStats): string;
var
  i: Integer;
begin
  Result := '{"metric": "' + HistogramName(Stats.HistogramKind) +
            '", "classes": [';
  for i := 0 to High(Stats.HistCounts) do
  begin
    if i > 0 then Result := Result + ', ';
    Result := Result + '{"range": "' + Stats.HistRanges[i] + '", "count": ' +
              IntToStr(Stats.HistCounts[i]) + '}';
  end;
  Result := Result + ']}';
end;

{-----------------------------------------------------------------------------
  BuildNGramsJSON : Tableau JSON compact des n-grams (--ngrams, C2-B).
  Chaque entrée expose : rank, words (tableau des mots), count.
  -----------------------------------------------------------------------------}
function BuildNGramsJSON(const Stats: TStats; ShowAll: Boolean; TopK: Integer): string;
var
  i, j, Limit: Integer;
begin
  Limit := EffectiveLimit(Length(Stats.NGrams), ShowAll, TopK) - 1;
  Result := '[';
  for i := 0 to Limit do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '{"rank": ' + IntToStr(i + 1) + ', "words": [';
    for j := 0 to High(Stats.NGrams[i].Words) do
    begin
      if j > 0 then Result := Result + ', ';
      Result := Result + '"' + JsonEscape(Stats.NGrams[i].Words[j]) + '"';
    end;
    Result := Result + '], "count": ' + IntToStr(Stats.NGrams[i].Count) + '}';
  end;
  Result := Result + ']';
end;

{-----------------------------------------------------------------------------
  BuildJSONCompact : Objet JSON complet sur UNE ligne (NDJSON, éléments des
  modes array/aggregate). Structure identique à ExportJSON (pretty).
  -----------------------------------------------------------------------------}
function BuildJSONCompact(const Stats: TStats; ShowAll: Boolean; LexicalStats: Boolean;
                          Readability: Boolean;
                          const CheckResults: TCheckResultArray): string;
var
  S: string;
  i: Integer;
  Lx: TLexicalStats;
  Rd: TReadabilityStats;
begin
  S := '{"file": "' + JsonEscape(Stats.Path) + '"';
  S := S + ', "generated": "' + JsonEscape(CurrentStamp) + '"';
  S := S + ', "tool": "fstats"';
  S := S + ', "version": "' + FSTATS_VERSION + '"';
  S := S + ', "schema_version": "1.0"';
  S := S + ', "statistics": {';
  S := S + '"lines": ' + IntToStr(Stats.LineCount);
  S := S + ', "words": ' + IntToStr(Stats.WordCount);
  S := S + ', "characters": ' + IntToStr(Stats.CharCount);
  S := S + ', "sentences": ' + IntToStr(Stats.SentenceCount);
  S := S + ', "avg_words_per_sentence": ' + IntToStr(Stats.AvgWordsPerSentence);
  S := S + ', "line_lengths": {"min": ' + IntToStr(Stats.MinLen);
  S := S + ', "max": ' + IntToStr(Stats.MaxLen);
  S := S + ', "average": ' + IntToStr(Stats.AvgLen) + '}';
  S := S + '}';
  S := S + ', "quality": {';
  S := S + '"invalid_utf8": ' + IntToStr(Stats.InvalidUTF8);
  S := S + ', "bom": ' + BoolToJSON(Stats.BOM);
  S := S + ', "crlf": ' + IntToStr(Stats.CRLF);
  S := S + ', "tabs": ' + IntToStr(Stats.Tabs);
  S := S + ', "nonprintable": ' + IntToStr(Stats.NonPrintable) + '}';
  // Checks (Cible 1, v2.6.0) : même position que dans ExportJSON (après
  // "quality"). Absent avec --summary-json et --csv (documenté).
  if Length(CheckResults) > 0 then
  begin
    S := S + ', "checks": [';
    for i := 0 to High(CheckResults) do
    begin
      if i > 0 then S := S + ',';
      if CheckResults[i].DeltaInf then
        S := S + '{"id": "' + JsonEscape(CheckResults[i].Id) +
          '", "metric": "' + JsonEscape(CheckResults[i].Metric) + '", "actual": 1e300'
      else
        S := S + '{"id": "' + JsonEscape(CheckResults[i].Id) +
          '", "metric": "' + JsonEscape(CheckResults[i].Metric) + '", "actual": ' +
          FormatFloatTrimSigned(CheckResults[i].Actual, 4);
      S := S + ', "op": "' + OpToStr(CheckResults[i].Op) + '"' +
        ', "threshold": ' + FormatFloatTrim(CheckResults[i].Threshold, 4) +
        ', "status": "' + CheckStatusStr(CheckResults[i].Status, False) + '"}';
    end;
    S := S + ']';
  end;
  if LexicalStats then
  begin
    Lx := ComputeLexical(Stats);
    S := S + ', "lexical": {"unique_words": ' + IntToStr(Lx.UniqueWords);
    S := S + ', "hapax": ' + IntToStr(Lx.Hapax);
    S := S + ', "type_token_ratio": ' + FormatFloatTrim(Lx.TypeTokenRatio, 6);
    S := S + ', "average_word_length": ' + FormatFloatTrim(Lx.AverageWordLength, 6);
    S := S + ', "entropy_bits_per_word": ' + FormatFloatTrim(Lx.EntropyBitsPerWord, 6) + '}';
  end;
  // Lisibilité (--readability, C2-C) : bloc additif, même position relative
  // que dans ExportJSON (pretty) — après le bloc lexical.
  if Readability then
  begin
    Rd := ComputeReadability(Stats);
    S := S + ', "readability": {"avg_sentence_words": ' + FormatFloatTrim(Rd.AvgSentenceWords, 6);
    S := S + ', "avg_word_chars": ' + FormatFloatTrim(Rd.AvgWordChars, 6);
    S := S + ', "pct_long_words": ' + FormatFloatTrim(Rd.PctLongWords, 6);
    S := S + ', "score": ' + FormatFloatTrim(Rd.Score, 6) + '}';
  end;
  // Structure (C2-B) : sections additionnelles quand activées
  if Stats.CharClassesEnabled then
    S := S + ', "char_classes": {"letters": ' + IntToStr(Stats.CharClasses[CC_LETTERS]) +
      ', "digits": ' + IntToStr(Stats.CharClasses[CC_DIGITS]) +
      ', "whitespace": ' + IntToStr(Stats.CharClasses[CC_WHITESPACE]) +
      ', "punctuation": ' + IntToStr(Stats.CharClasses[CC_PUNCTUATION]) +
      ', "control": ' + IntToStr(Stats.CharClasses[CC_CONTROL]) +
      ', "other": ' + IntToStr(Stats.CharClasses[CC_OTHER]) + '}';
  if Stats.HistogramKind <> hkNone then
    S := S + ', "histogram": ' + BuildHistogramJSON(Stats);
  if Stats.NGramSize > 0 then
    S := S + ', "ngrams": ' + BuildNGramsJSON(Stats, ShowAll, TopNgramsLimit);
  S := S + ', "top_characters": ' + BuildTopCharsJSON(Stats, ShowAll, TopCharsLimit);
  S := S + ', "top_words": ' + BuildTopWordsJSON(Stats, ShowAll, TopWordsLimit);
  S := S + ', "longest_lines": ' + BuildTopLinesJSON(Stats, ShowAll);
  S := S + '}';
  Result := S;
end;

{-----------------------------------------------------------------------------
  BuildSummaryJSON : Objet JSON PLAT par fichier (--summary-json), conçu
  pour les scripts/jq : compteurs et métriques en champs de premier niveau.
  -----------------------------------------------------------------------------}
function BuildSummaryJSON(const Stats: TStats; LexicalStats: Boolean;
                          Readability: Boolean): string;
var
  S: string;
  Lx: TLexicalStats;
  Rd: TReadabilityStats;
begin
  S := '{"file": "' + JsonEscape(Stats.Path) + '"';
  S := S + ', "tool": "fstats"';
  S := S + ', "version": "' + FSTATS_VERSION + '"';
  S := S + ', "schema_version": "1.0"';
  S := S + ', "lines": ' + IntToStr(Stats.LineCount);
  S := S + ', "words": ' + IntToStr(Stats.WordCount);
  S := S + ', "characters": ' + IntToStr(Stats.CharCount);
  S := S + ', "sentences": ' + IntToStr(Stats.SentenceCount);
  S := S + ', "avg_words_per_sentence": ' + IntToStr(Stats.AvgWordsPerSentence);
  S := S + ', "line_min": ' + IntToStr(Stats.MinLen);
  S := S + ', "line_max": ' + IntToStr(Stats.MaxLen);
  S := S + ', "line_avg": ' + IntToStr(Stats.AvgLen);
  S := S + ', "invalid_utf8": ' + IntToStr(Stats.InvalidUTF8);
  S := S + ', "bom": ' + BoolToJSON(Stats.BOM);
  S := S + ', "crlf": ' + IntToStr(Stats.CRLF);
  S := S + ', "tabs": ' + IntToStr(Stats.Tabs);
  S := S + ', "nonprintable": ' + IntToStr(Stats.NonPrintable);
  if LexicalStats then
  begin
    Lx := ComputeLexical(Stats);
    S := S + ', "unique_words": ' + IntToStr(Lx.UniqueWords);
    S := S + ', "hapax": ' + IntToStr(Lx.Hapax);
    S := S + ', "type_token_ratio": ' + FormatFloatTrim(Lx.TypeTokenRatio, 6);
    S := S + ', "average_word_length": ' + FormatFloatTrim(Lx.AverageWordLength, 6);
    S := S + ', "entropy_bits_per_word": ' + FormatFloatTrim(Lx.EntropyBitsPerWord, 6);
  end;
  // Structure (C2-B) : valeurs JSON additionnelles en fin d'objet (l'objet
  // reste sur une ligne, parseable ligne à ligne — les valeurs peuvent être
  // des objets/tableaux JSON)
  if Stats.CharClassesEnabled then
    S := S + ', "char_classes": {"letters": ' + IntToStr(Stats.CharClasses[CC_LETTERS]) +
      ', "digits": ' + IntToStr(Stats.CharClasses[CC_DIGITS]) +
      ', "whitespace": ' + IntToStr(Stats.CharClasses[CC_WHITESPACE]) +
      ', "punctuation": ' + IntToStr(Stats.CharClasses[CC_PUNCTUATION]) +
      ', "control": ' + IntToStr(Stats.CharClasses[CC_CONTROL]) +
      ', "other": ' + IntToStr(Stats.CharClasses[CC_OTHER]) + '}';
  if Stats.HistogramKind <> hkNone then
    S := S + ', "histogram": ' + BuildHistogramJSON(Stats);
  if Stats.NGramSize > 0 then
    S := S + ', "ngrams": ' + BuildNGramsJSON(Stats, True, TopNgramsLimit);
  // Lisibilité (--readability, C2-C) : clés plates en fin d'objet (6 décimales,
  // comme les autres métriques du summary plat).
  if Readability then
  begin
    Rd := ComputeReadability(Stats);
    S := S + ', "avg_sentence_words": ' + FormatFloatTrim(Rd.AvgSentenceWords, 6);
    S := S + ', "avg_word_chars": ' + FormatFloatTrim(Rd.AvgWordChars, 6);
    S := S + ', "pct_long_words": ' + FormatFloatTrim(Rd.PctLongWords, 6);
    S := S + ', "readability_score": ' + FormatFloatTrim(Rd.Score, 6);
  end;
  S := S + '}';
  Result := S;
end;

{=============================================================================
  EXPORT CSV - FORMAT RFC 4180 SÉCURISÉ
  =============================================================================
  Objectif : Générer un CSV valide avec échappement des caractères spéciaux
  Sécurité :
    - Remplace les vrais sauts de ligne par des séquences \n pour garder 1 ligne/enregistrement
    - Échappe les guillemets et les virgules dans les champs
    - Utilise des guillemets autour des champs contenant des caractères spéciaux
  =============================================================================}
{-----------------------------------------------------------------------------
  CsvEscape — CORRECTION : boucle manuelle + codes numériques
-----------------------------------------------------------------------------}
function CsvEscape(const S: string): string;
var
  CleanS: string;
  i: Integer;
  C: Char;
  HasSpecial: Boolean;
begin
  { Passe 1 : neutraliser les caractères de contrôle }
  CleanS := '';
  for i := 1 to Length(S) do
  begin
    C := S[i];
    case Ord(C) of
      10: CleanS := CleanS + '\n';
      13: CleanS := CleanS + '\r';
      9:  CleanS := CleanS + '\t';
      else CleanS := CleanS + C;
    end;
  end;

  { Passe 2 : détecter guillemets (#34) et virgules (#44) }
  HasSpecial := False;
  for i := 1 to Length(CleanS) do
  begin
    if (Ord(CleanS[i]) = 34) or (Ord(CleanS[i]) = 44) then
    begin
      HasSpecial := True;
      Break;
    end;
  end;

  { Passe 3 : échapper si nécessaire (RFC 4180) }
  if HasSpecial then
    Result := #34 + StringReplace(CleanS, #34, #34#34, [rfReplaceAll]) + #34
  else
    Result := CleanS;
end;

procedure ExportCSV(const Stats: TStats; ShowAll: Boolean; LexicalStats: Boolean;
                    Readability: Boolean; CsvKind: TCsvKind);
var
  i, Limit: Integer;
  Lx: TLexicalStats;
  Rd: TReadabilityStats;
begin
  // CSV v2 (C2-A) : en-tête fixe file,type,rank,value,code_point,count,length.
  // Rupture assumée et documentée (README) par rapport au format v1 :
  //  - --csv=summary : une ligne par métrique (value = nom, count = valeur)
  //  - --csv=words   : une ligne par mot du top (length = code points)
  //  - --csv=chars   : une ligne par caractère du top (length = 1)
  // Les valeurs calculées restent strictement identiques au mode console/JSON.
  WriteLn('file,type,rank,value,code_point,count,length');

  case CsvKind of
    ckSummary:
      begin
        WriteLn(CsvEscape(Stats.Path), ',summary,,lines,,', Stats.LineCount, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,words,,', Stats.WordCount, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,characters,,', Stats.CharCount, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,sentences,,', Stats.SentenceCount, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,avg_words_per_sentence,,', Stats.AvgWordsPerSentence, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,line_min,,', Stats.MinLen, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,line_max,,', Stats.MaxLen, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,line_avg,,', Stats.AvgLen, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,invalid_utf8,,', Stats.InvalidUTF8, ',');
        if Stats.BOM then
          WriteLn(CsvEscape(Stats.Path), ',summary,,bom,,1,')
        else
          WriteLn(CsvEscape(Stats.Path), ',summary,,bom,,0,');
        WriteLn(CsvEscape(Stats.Path), ',summary,,crlf,,', Stats.CRLF, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,tabs,,', Stats.Tabs, ',');
        WriteLn(CsvEscape(Stats.Path), ',summary,,nonprintable,,', Stats.NonPrintable, ',');
        if LexicalStats then
        begin
          Lx := ComputeLexical(Stats);
          WriteLn(CsvEscape(Stats.Path), ',summary,,unique_words,,', Lx.UniqueWords, ',');
          WriteLn(CsvEscape(Stats.Path), ',summary,,hapax,,', Lx.Hapax, ',');
          WriteLn(CsvEscape(Stats.Path), ',summary,,type_token_ratio,,', FormatFloatTrim(Lx.TypeTokenRatio, 6), ',');
          WriteLn(CsvEscape(Stats.Path), ',summary,,average_word_length,,', FormatFloatTrim(Lx.AverageWordLength, 6), ',');
          WriteLn(CsvEscape(Stats.Path), ',summary,,entropy_bits_per_word,,', FormatFloatTrim(Lx.EntropyBitsPerWord, 6), ',');
        end;
        // Lisibilité (--readability, C2-C) : 4 lignes summary additionnelles
        // (6 décimales, comme les métriques lexicales).
        if Readability then
        begin
          Rd := ComputeReadability(Stats);
          WriteLn(CsvEscape(Stats.Path), ',summary,,avg_sentence_words,,', FormatFloatTrim(Rd.AvgSentenceWords, 6), ',');
          WriteLn(CsvEscape(Stats.Path), ',summary,,avg_word_chars,,', FormatFloatTrim(Rd.AvgWordChars, 6), ',');
          WriteLn(CsvEscape(Stats.Path), ',summary,,pct_long_words,,', FormatFloatTrim(Rd.PctLongWords, 6), ',');
          WriteLn(CsvEscape(Stats.Path), ',summary,,readability_score,,', FormatFloatTrim(Rd.Score, 6), ',');
        end;
      end;
    ckChars:
      begin
        Limit := EffectiveLimit(Length(Stats.Freq), ShowAll, TopCharsLimit);
        for i := 0 to Limit - 1 do
          WriteLn(CsvEscape(Stats.Path), ',character,', i + 1, ',',
                  CsvEscape(VisualChar(Stats.Freq[i].CodePoint)), ',',
                  UnicodeCode(Stats.Freq[i].CodePoint), ',',
                  Stats.Freq[i].Count, ',1');
      end;
    ckWords:
      begin
        Limit := EffectiveLimit(Length(Stats.Words), ShowAll, TopWordsLimit);
        for i := 0 to Limit - 1 do
          WriteLn(CsvEscape(Stats.Path), ',word,', i + 1, ',',
                  CsvEscape(Stats.Words[i].Word), ',,',
                  Stats.Words[i].Count, ',', UTF8Length(Stats.Words[i].Word));
      end;
  end;
end;

{-----------------------------------------------------------------------------
  PrintUsage : Affiche l'aide en ligne de commande
  Entrée  : Out - Flux de sortie (Output pour --help, ErrOutput pour une
                  erreur d'utilisation)
  -----------------------------------------------------------------------------}
procedure PrintUsage(var Out: Text);
begin
  WriteLn(Out, 'Usage: fstats [options] <fichier|glob|-> [fichier2 ...]');
  WriteLn(Out);
  WriteLn(Out, 'Analyse UTF-8 stricte : comptage de caracteres, de mots, de');
  WriteLn(Out, 'lignes et de phrases, compteurs qualite, export JSON/CSV,');
  WriteLn(Out, 'sortie console alignee, ASCII pur.');
  WriteLn(Out);
  WriteLn(Out, 'Entree standard et fichiers :');
  WriteLn(Out, '  -                 Lit l''entree standard (stdin) en UTF-8');
  WriteLn(Out, '  --stdin           Alias de - (non melangeable avec fichiers)');
  WriteLn(Out, '  *.txt, **/*.md    Patterns glob resolus en interne (les');
  WriteLn(Out, '                    shells Windows n''expandent pas les globs)');
  WriteLn(Out, '  --recursive=DIR   Parcourt l''arbre de DIR (repetable)');
  WriteLn(Out, '  --include=GLOB    Filtre d''inclusion pour --recursive (rep.)');
  WriteLn(Out, '  --exclude=GLOB    Filtre d''exclusion pour --recursive (rep.)');
  WriteLn(Out, '  --max-depth=N     Profondeur max pour --recursive (0 = racine)');
  WriteLn(Out);
  WriteLn(Out, 'Options d''affichage :');
  WriteLn(Out, '  --char            Stats de caracteres uniquement');
  WriteLn(Out, '  --word            Stats de mots uniquement');
  WriteLn(Out, '  --line            Stats de lignes uniquement');
  WriteLn(Out, '  --all             Toutes les donnees (pas de limite Top 10)');
  WriteLn(Out);
  WriteLn(Out, 'Analyse lexicale (v2.3.0) :');
  WriteLn(Out, '  --word-mode=MODE  raw | ascii | unicode (tokenisation des mots)');
  WriteLn(Out, '  --casefold=MODE   ascii | unicode | none (repli de casse)');
  WriteLn(Out, '  --lexical-stats   Unique, hapax, TTR, longueur moy., entropie');
  WriteLn(Out, '  --top-words=N     Limite de la section mots (0 = tous)');
  WriteLn(Out, '  --top-chars=N     Limite de la section caracteres (0 = tous)');
  WriteLn(Out, '  --max-unique=N    Borne memoire des types de mots (def. 100000)');
  WriteLn(Out);
  WriteLn(Out, 'Structure (v2.4.0) :');
  WriteLn(Out, '  --ngrams=N        N-grams sur les mots du mode courant (1..5)');
  WriteLn(Out, '  --top-ngrams=K    Limite top-K des n-grams (def. 10, 0 = tous)');
  WriteLn(Out, '  --stopwords=L     fr | en | none : retire les mots vides du');
  WriteLn(Out, '                    flux n-gram uniquement (sans --ngrams, ignore)');
  WriteLn(Out, '  --histogram=M     line_length | word_length | words_per_sentence');
  WriteLn(Out, '                    (barres ASCII, classes documentees)');
  WriteLn(Out, '  --char-classes    Classes de caracteres (6 classes, somme =');
  WriteLn(Out, '                    characters)');
  WriteLn(Out);
  WriteLn(Out, 'Lisibilite (v2.5.0) :');
  WriteLn(Out, '  --readability     Metriques de lisibilite + score 0-100');
  WriteLn(Out, '                    (sans syllabes, inspire de Flesch)');
  WriteLn(Out);
  WriteLn(Out, 'Checks et comparaison (v2.6.0) :');
  WriteLn(Out, '  --check           Mode check : gate CI (exit 2/3)');
  WriteLn(Out, '  --fail-if=SPEC    Check bloquant : METRIQUE OPERATEUR SEUIL');
  WriteLn(Out, '                    (ex. --fail-if lines>100, --fail-if');
  WriteLn(Out, '                    max_line_length<=120) ; repetable');
  WriteLn(Out, '  --warn-if=SPEC    Check non bloquant (meme grammaire)');
  WriteLn(Out, '  --compare=F       Baseline NDJSON (sortie --summary-json)');
  WriteLn(Out, '  --fail-on-delta=S Check de derive : METRIQUE>X (X = pourcent,');
  WriteLn(Out, '                    ex. --fail-on-delta lines>10) ; repetable');
  WriteLn(Out);
  WriteLn(Out, 'Formats d''export :');
  WriteLn(Out, '  --json            Export JSON : 1 fichier = objet unique,');
  WriteLn(Out, '                    plusieurs = NDJSON (1 objet par ligne)');
  WriteLn(Out, '  --json-mode=MODE  ndjson | array | aggregate (avec --json)');
  WriteLn(Out, '  --summary-json    Objet JSON plat par fichier (scripts/jq)');
  WriteLn(Out, '  --csv[=MODE]      Export CSV v2 : summary (defaut) | words | chars');
  WriteLn(Out, '  --out=FICHIER     Rediriger la sortie vers un fichier');
  WriteLn(Out, '  --quiet           Pas de confirmation console avec --out');
  WriteLn(Out);
  WriteLn(Out, 'Divers :');
  WriteLn(Out, '  --color           Coloriage minimal des titres (console)');
  WriteLn(Out, '  --no-color        Pas de couleur (defaut)');
  WriteLn(Out, '  --version         Affiche la version et quitte');
  WriteLn(Out, '  --help, -h        Affiche cette aide et quitte');
  WriteLn(Out);
  WriteLn(Out, 'Codes de retour : 0 si succes, 1 en cas d''erreur (fichier');
  WriteLn(Out, 'introuvable, glob sans correspondance, option invalide,');
  WriteLn(Out, 'sortie inecrivable, stdin melange avec des fichiers, etc.).');
  WriteLn(Out, 'En mode check : 2 si au moins un check echoue, 3 si warnings');
  WriteLn(Out, 'seulement (le mode analyse garde 0/1).');
end;

{=============================================================================
  FONCTION PRINCIPALE - POINT D'ENTRÉE
  =============================================================================
  Objectif : Parser les arguments, orchestrer l'analyse, gérer les exports
  Sécurité :
    - Validation des chemins de fichiers (anti-path traversal)
    - Gestion d'erreurs sans fuite d'informations sensibles
    - Redirection propre de la sortie avec gestion des ressources
  =============================================================================}
var
  i: Integer;
  Param, ParamOrig, OutFileName: string;
  OptChar, OptWord, OptLine, OptJSON, OptCSV, OptAll: Boolean;
  OptColor, OptQuiet, OptSummaryJSON, UseStdin: Boolean;
  RawFiles, Files, RecursiveDirs, IncludePatterns, ExcludePatterns: TStringList;
  JsonParts: TStringList;      // Objets JSON compacts (modes array/aggregate)
  Stats: TStats;
  TestFile: Text;
  HadError: Boolean;  // True si au moins un fichier a échoué (exit code 1)
  JsonMode: TJsonMode;
  JsonModeExplicit: Boolean;
  MaxDepth: Integer;           // -1 = illimité (défaut)
  V: string;
  Code: Integer;
  TotalFiles, TotalLines, TotalWords, TotalChars, TotalSentences: Int64;
  // Options d'analyse lexicale (incrément C2-A)
  WordMode: TWordMode;         // --word-mode (raw par défaut)
  CaseFoldMode: TCaseFold;     // --casefold (ascii par défaut)
  CsvKind: TCsvKind;           // --csv=summary|words|chars
  OptLexicalStats: Boolean;    // --lexical-stats
  OptReadability: Boolean;     // --readability (C2-C)
  MaxUnique: Int64;            // --max-unique=N (borne mémoire des types)
  // Options structure (incrément C2-B)
  NGramSize: Integer;          // --ngrams=N (1..5, 0 = désactivé)
  StopWordMode: TStopWord;     // --stopwords=fr|en|none
  HistogramKindOpt: THistogramKind; // --histogram=...
  OptCharClasses: Boolean;     // --char-classes
  SOpts: TStructureOptions;    // Options structure transmises à l'analyse
  // Totaux agrégés (--json-mode=aggregate, C2-B) : char_classes et histogramme
  // sont sommés classe par classe ; les n-grams ne sont PAS agrégés (limitation
  // documentée : présents par fichier uniquement).
  TotalCharClasses: array[0..CC_CLASS_COUNT - 1] of Int64;
  TotalHistCounts: array[0..6] of Int64;
  HistRangesTotal: TStringArray;
  k: Integer;
  // C2 (v2.6.0) : moteur de checks et comparaison baseline (Cible 1, B et C)
  OptCheck: Boolean;               // --check (mode check explicite)
  CheckMode: Boolean;              // mode check actif (explicite ou implicite)
  CompareFile: string;             // --compare BASELINE (fichier baseline NDJSON)
  Checks: TCheckArray;             // checks définis (--fail-if/--warn-if/--fail-on-delta)
  Baseline: TBaselineArray;        // entrées baseline lues (--compare)
  CheckResults: TCheckResultArray; // résultats du fichier courant
  HasFail, HasWarn: Boolean;       // pire statut multi-fichiers (fail > warn > ok)
  FailOnDeltaCount: Integer;       // nombre de --fail-on-delta (validation)
  CheckMetric: string;             // valeurs temporaires de parsing des checks
  CheckOp: TCheckOp;
  CheckThr: Double;
  DeltaMetric: string;
  DeltaThr: Double;
  IsWarnCheck: Boolean;
  OpToken: string;
begin
  {===========================================================================
  CONFIGURATION INITIALE
  ===========================================================================}
  // Forcer l'encodage système en UTF-8 pour éviter les conversions automatiques
  // qui corrompent les caractères Unicode dans les chaînes AnsiString
  DefaultSystemCodePage := CP_UTF8_LOCAL;

  // Forcer le code page UTF-8 sur les flux texte de sortie (stdout/stderr).
  // CORRECTION : sans cela, sous Windows, le code page texte de stdout/stderr
  // est hérité de la console au démarrage (souvent CP850/CP437, voire CP65001
  // selon l'état de la console) : les octets UTF-8 écrits dans un fichier ou
  // un pipe étaient convertis en mojibake de façon NON DÉTERMINISTE (la
  // première exécution dans une console différait des suivantes). Avec le
  // code page texte forcé à UTF-8, l'écriture est l'identité octet à octet.
  SetTextCodePage(Output, CP_UTF8_LOCAL);
  SetTextCodePage(ErrOutput, CP_UTF8_LOCAL);

  {$IFDEF MSWINDOWS}
  // Windows : configurer la console pour UTF-8 et support ANSI
  ConfigureConsoleForUTF8;
  {$ENDIF}

  // Mémoriser si la sortie standard est une console (utilisé par --color)
  StdOutIsConsole := OutputIsConsole;

  {===========================================================================
  INITIALISATION DES OPTIONS
  ===========================================================================}
  NoColor := True;   // Par défaut : pas de couleurs (ASCII pur, pipe-friendly)

  OptChar := False;
  OptWord := False;
  OptLine := False;
  OptJSON := False;
  OptCSV := False;
  OptAll := False;
  OptColor := False;
  OptQuiet := False;
  OptSummaryJSON := False;
  UseStdin := False;
  JsonMode := jmAuto;
  JsonModeExplicit := False;
  MaxDepth := -1;
  HadError := False;
  // Analyse lexicale (C2-A) : défauts = comportement historique strict
  WordMode := wmRaw;
  CaseFoldMode := cfAscii;
  CsvKind := ckSummary;
  OptLexicalStats := False;
  OptReadability := False;     // --readability (C2-C) : désactivé par défaut
  TopWordsLimit := DEFAULT_TOP_LIMIT;
  TopCharsLimit := DEFAULT_TOP_LIMIT;
  MaxUnique := DEFAULT_MAX_UNIQUE;
  // Structure (C2-B) : défauts = sections désactivées
  NGramSize := 0;
  TopNgramsLimit := DEFAULT_TOP_LIMIT;
  StopWordMode := swNone;
  HistogramKindOpt := hkNone;
  OptCharClasses := False;
  // C2 (v2.6.0) : défauts du moteur de checks
  OptCheck := False;
  CheckMode := False;
  CompareFile := '';
  SetLength(Checks, 0);
  SetLength(Baseline, 0);
  HasFail := False;
  HasWarn := False;
  FailOnDeltaCount := 0;

  OutFileName := '';  // Pas de redirection de sortie par défaut

  // Listes de travail
  RawFiles := TStringList.Create;         // Arguments positionnels (avant résolution)
  Files := TStringList.Create;            // Fichiers résolus (triés, dédoublonnés)
  RecursiveDirs := TStringList.Create;    // --recursive=DIR (répétable)
  IncludePatterns := TStringList.Create;  // --include=PATTERN (répétable)
  ExcludePatterns := TStringList.Create;  // --exclude=PATTERN (répétable)
  JsonParts := TStringList.Create;        // JSON compacts (array/aggregate)

  try
    {=========================================================================
    PARSING DES ARGUMENTS - CASE-INSENSITIVE ET SÉCURISÉ
    =========================================================================}
    i := 1;
    while i <= ParamCount do
    begin
      ParamOrig := ParamStr(i);
      Param := LowerCase(ParamOrig);  // Normalisation pour comparaison insensible à la casse

      // Options de filtrage d'affichage
      if Param = '--char' then
        OptChar := True
      else if Param = '--word' then
        OptWord := True
      else if Param = '--line' then
        OptLine := True

      // Options de format d'export
      else if Param = '--json' then
        OptJSON := True
      else if Param = '--csv' then
      begin
        OptCSV := True;
        CsvKind := ckSummary;  // --csv seul = summary (rétro-compat du drapeau)
      end
      else if (Copy(Param, 1, 6) = '--csv=') or (Copy(Param, 1, 6) = '--csv:') then
      begin
        V := LowerCase(Copy(ParamOrig, 7, Length(ParamOrig)));
        if V = 'summary' then CsvKind := ckSummary
        else if V = 'words' then CsvKind := ckWords
        else if V = 'chars' then CsvKind := ckChars
        else
        begin
          WriteLn(ErrOutput, 'Erreur: --csv attend "summary", "words" ou "chars" (reçu "', V, '")');
          Halt(1);
        end;
        OptCSV := True;
      end
      else if Param = '--summary-json' then
        OptSummaryJSON := True

      // Option d'étendue des données
      else if Param = '--all' then
        OptAll := True

      // Entrée standard (marqueur résolu après le parsing)
      else if (Param = '-') or (Param = '--stdin') then
        RawFiles.Add('-')

      // Options d'affichage/couleurs
      else if Param = '--color' then
        OptColor := True
      else if Param = '--no-color' then
        NoColor := True
      else if Param = '--quiet' then
        OptQuiet := True

      // Aide et version
      else if (Param = '--help') or (Param = '-h') then
      begin
        PrintUsage(Output);
        Halt(0);
      end
      else if Param = '--version' then
      begin
        WriteLn('fstats ', FSTATS_VERSION);
        Halt(0);
      end

      // Option de redirection de sortie (supporte --out= et --out:)
      else if (Copy(Param, 1, 6) = '--out=') or (Copy(Param, 1, 6) = '--out:') then
      begin
        OutFileName := Copy(ParamOrig, 7, Length(ParamOrig));
        if OutFileName = '' then
        begin
          WriteLn(ErrOutput, 'Erreur: nom de fichier manquant après --out=');
          Halt(1);
        end;
      end
      else if Param = '--out' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --out=nom_fichier (avec le signe égal)');
        Halt(1);
      end

      // Parcours récursif (répétable)
      else if (Copy(Param, 1, 12) = '--recursive=') or (Copy(Param, 1, 12) = '--recursive:') then
      begin
        V := Copy(ParamOrig, 13, Length(ParamOrig));
        if V = '' then
        begin
          WriteLn(ErrOutput, 'Erreur: répertoire manquant après --recursive=');
          Halt(1);
        end;
        RecursiveDirs.Add(V);
      end

      // Filtres d'inclusion/exclusion (répétables)
      else if (Copy(Param, 1, 10) = '--include=') or (Copy(Param, 1, 10) = '--include:') then
      begin
        V := Copy(ParamOrig, 11, Length(ParamOrig));
        if V = '' then
        begin
          WriteLn(ErrOutput, 'Erreur: motif manquant après --include=');
          Halt(1);
        end;
        IncludePatterns.Add(NormalizePath(V));
      end
      else if (Copy(Param, 1, 10) = '--exclude=') or (Copy(Param, 1, 10) = '--exclude:') then
      begin
        V := Copy(ParamOrig, 11, Length(ParamOrig));
        if V = '' then
        begin
          WriteLn(ErrOutput, 'Erreur: motif manquant après --exclude=');
          Halt(1);
        end;
        ExcludePatterns.Add(NormalizePath(V));
      end

      // Profondeur maximale du parcours récursif
      else if (Copy(Param, 1, 12) = '--max-depth=') or (Copy(Param, 1, 12) = '--max-depth:') then
      begin
        V := Copy(ParamOrig, 13, Length(ParamOrig));
        Val(V, MaxDepth, Code);
        if (Code <> 0) or (MaxDepth < 0) then
        begin
          WriteLn(ErrOutput, 'Erreur: --max-depth attend un entier >= 0 (reçu "', V, '")');
          Halt(1);
        end;
      end

      // Mode JSON multi-fichiers (implique --json)
      else if (Copy(Param, 1, 12) = '--json-mode=') or (Copy(Param, 1, 12) = '--json-mode:') then
      begin
        V := LowerCase(Copy(ParamOrig, 13, Length(ParamOrig)));
        if V = 'ndjson' then
          JsonMode := jmNDJSON
        else if V = 'array' then
          JsonMode := jmArray
        else if V = 'aggregate' then
          JsonMode := jmAggregate
        else
        begin
          WriteLn(ErrOutput, 'Erreur: --json-mode attend "ndjson", "array" ou "aggregate" (reçu "', V, '")');
          Halt(1);
        end;
        JsonModeExplicit := True;
        OptJSON := True;  // --json-mode est un format JSON à part entière
      end
      else if Param = '--json-mode' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --json-mode=ndjson|array|aggregate');
        Halt(1);
      end

      // Analyse lexicale (incrément C2-A)
      else if (Copy(Param, 1, 12) = '--word-mode=') or (Copy(Param, 1, 12) = '--word-mode:') then
      begin
        V := LowerCase(Copy(ParamOrig, 13, Length(ParamOrig)));
        if V = 'raw' then WordMode := wmRaw
        else if V = 'ascii' then WordMode := wmAscii
        else if V = 'unicode' then WordMode := wmUnicode
        else
        begin
          WriteLn(ErrOutput, 'Erreur: --word-mode attend "raw", "ascii" ou "unicode" (reçu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--word-mode' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --word-mode=raw|ascii|unicode');
        Halt(1);
      end
      else if (Copy(Param, 1, 11) = '--casefold=') or (Copy(Param, 1, 11) = '--casefold:') then
      begin
        V := LowerCase(Copy(ParamOrig, 12, Length(ParamOrig)));
        if V = 'ascii' then CaseFoldMode := cfAscii
        else if V = 'unicode' then CaseFoldMode := cfUnicode
        else if V = 'none' then CaseFoldMode := cfNone
        else
        begin
          WriteLn(ErrOutput, 'Erreur: --casefold attend "ascii", "unicode" ou "none" (reçu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--casefold' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --casefold=ascii|unicode|none');
        Halt(1);
      end
      else if Param = '--lexical-stats' then
        OptLexicalStats := True
      else if Param = '--readability' then
        OptReadability := True
      else if (Copy(Param, 1, 12) = '--top-words=') or (Copy(Param, 1, 12) = '--top-words:') then
      begin
        V := Copy(ParamOrig, 13, Length(ParamOrig));
        Val(V, TopWordsLimit, Code);
        if (Code <> 0) or (TopWordsLimit < 0) then
        begin
          WriteLn(ErrOutput, 'Erreur: --top-words attend un entier >= 0 (reçu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--top-words' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --top-words=N (0 = tous)');
        Halt(1);
      end
      else if (Copy(Param, 1, 12) = '--top-chars=') or (Copy(Param, 1, 12) = '--top-chars:') then
      begin
        V := Copy(ParamOrig, 13, Length(ParamOrig));
        Val(V, TopCharsLimit, Code);
        if (Code <> 0) or (TopCharsLimit < 0) then
        begin
          WriteLn(ErrOutput, 'Erreur: --top-chars attend un entier >= 0 (reçu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--top-chars' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --top-chars=N (0 = tous)');
        Halt(1);
      end
      else if (Copy(Param, 1, 13) = '--max-unique=') or (Copy(Param, 1, 13) = '--max-unique:') then
      begin
        V := Copy(ParamOrig, 14, Length(ParamOrig));
        Val(V, MaxUnique, Code);
        if (Code <> 0) or (MaxUnique < 1) then
        begin
          WriteLn(ErrOutput, 'Erreur: --max-unique attend un entier >= 1 (reçu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--max-unique' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --max-unique=N (entier >= 1)');
        Halt(1);
      end

      // Structure (incrément C2-B)
      else if (Copy(Param, 1, 9) = '--ngrams=') or (Copy(Param, 1, 9) = '--ngrams:') then
      begin
        V := Copy(ParamOrig, 10, Length(ParamOrig));
        Val(V, NGramSize, Code);
        if (Code <> 0) or (NGramSize < 1) or (NGramSize > 5) then
        begin
          WriteLn(ErrOutput, 'Erreur: --ngrams attend un entier de 1 a 5 (recu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--ngrams' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --ngrams=N (entier de 1 a 5)');
        Halt(1);
      end
      else if (Copy(Param, 1, 13) = '--top-ngrams=') or (Copy(Param, 1, 13) = '--top-ngrams:') then
      begin
        V := Copy(ParamOrig, 14, Length(ParamOrig));
        Val(V, TopNgramsLimit, Code);
        if (Code <> 0) or (TopNgramsLimit < 0) then
        begin
          WriteLn(ErrOutput, 'Erreur: --top-ngrams attend un entier >= 0 (recu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--top-ngrams' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --top-ngrams=N (0 = tous)');
        Halt(1);
      end
      else if (Copy(Param, 1, 12) = '--stopwords=') or (Copy(Param, 1, 12) = '--stopwords:') then
      begin
        V := LowerCase(Copy(ParamOrig, 13, Length(ParamOrig)));
        if V = 'fr' then StopWordMode := swFR
        else if V = 'en' then StopWordMode := swEN
        else if V = 'none' then StopWordMode := swNone
        else
        begin
          WriteLn(ErrOutput, 'Erreur: --stopwords attend "fr", "en" ou "none" (recu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--stopwords' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --stopwords=fr|en|none');
        Halt(1);
      end
      else if (Copy(Param, 1, 12) = '--histogram=') or (Copy(Param, 1, 12) = '--histogram:') then
      begin
        V := LowerCase(Copy(ParamOrig, 13, Length(ParamOrig)));
        // Les exemples de la roadmap (§6.6) utilisent des tirets
        // (line-length, word-length, words-per-sentence) ; la spec des
        // tirets-bas : les deux formes sont acceptées et équivalentes.
        V := StringReplace(V, '-', '_', [rfReplaceAll]);
        if V = 'line_length' then HistogramKindOpt := hkLineLength
        else if V = 'word_length' then HistogramKindOpt := hkWordLength
        else if V = 'words_per_sentence' then HistogramKindOpt := hkWordsPerSentence
        else
        begin
          WriteLn(ErrOutput, 'Erreur: --histogram attend "line_length", "word_length" ou "words_per_sentence" (recu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--histogram' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --histogram=line_length|word_length|words_per_sentence');
        Halt(1);
      end
      else if Param = '--char-classes' then
        OptCharClasses := True

      // C2 (v2.6.0) : moteur de checks — --check, --fail-if, --warn-if,
      // --compare et --fail-on-delta. --fail-if/--warn-if/--compare/
      // --fail-on-delta activent aussi le mode check (mode implicite).
      else if Param = '--check' then
        OptCheck := True
      else if (Param = '--compare') or (Copy(Param, 1, 10) = '--compare=') or
              (Copy(Param, 1, 10) = '--compare:') then
      begin
        if Param = '--compare' then
        begin
          if i >= ParamCount then
          begin
            WriteLn(ErrOutput, 'Erreur: nom de fichier baseline manquant après --compare');
            Halt(1);
          end;
          Inc(i);
          CompareFile := ParamStr(i);
        end
        else
          CompareFile := Copy(ParamOrig, 11, Length(ParamOrig));
        if CompareFile = '' then
        begin
          WriteLn(ErrOutput, 'Erreur: nom de fichier baseline manquant après --compare');
          Halt(1);
        end;
      end
      else if (Param = '--fail-if') or (Param = '--warn-if') or
              (Copy(Param, 1, 10) = '--fail-if=') or (Copy(Param, 1, 10) = '--fail-if:') or
              (Copy(Param, 1, 10) = '--warn-if=') or (Copy(Param, 1, 10) = '--warn-if:') then
      begin
        IsWarnCheck := (Param = '--warn-if') or
                       (Copy(Param, 1, 10) = '--warn-if=') or
                       (Copy(Param, 1, 10) = '--warn-if:');
        // Valeur : en ligne (--fail-if=SPEC) ou argument(s) suivant(s)
        if (Copy(Param, 1, 10) = '--fail-if=') or (Copy(Param, 1, 10) = '--fail-if:') or
           (Copy(Param, 1, 10) = '--warn-if=') or (Copy(Param, 1, 10) = '--warn-if:') then
          V := Copy(ParamOrig, 11, Length(ParamOrig))
        else
        begin
          if i >= ParamCount then
          begin
            WriteLn(ErrOutput, 'Erreur: --fail-if/--warn-if : valeur manquante (METRIQUE OPERATEUR SEUIL)');
            Halt(1);
          end;
          Inc(i);
          V := ParamStr(i);
        end;
        // Grammaire : METRIQUE [espaces] OPERATEUR [espaces] SEUIL — si la
        // valeur ne contient pas d'opérateur, l'opérateur (et le seuil)
        // peuvent être passés en argument(s) séparé(s) : --fail-if lines > 2
        if not ContainsCheckOp(V) then
        begin
          if (i < ParamCount) and IsOpToken(ParamStr(i + 1)) then
          begin
            Inc(i);
            OpToken := ParamStr(i);
            if i >= ParamCount then
            begin
              WriteLn(ErrOutput, 'Erreur: --fail-if/--warn-if : seuil manquant après l''opérateur "', OpToken, '"');
              Halt(1);
            end;
            Inc(i);
            V := V + OpToken + ParamStr(i);
          end;
        end;
        Code := ParseCheckSpec(V, CheckMetric, CheckOp, CheckThr);
        case Code of
          0: ;
          1: begin
               WriteLn(ErrOutput, 'Erreur: --fail-if/--warn-if : métrique manquante ou invalide dans "', V, '"');
               Halt(1);
             end;
          2: begin
               WriteLn(ErrOutput, 'Erreur: --fail-if/--warn-if : opérateur manquant dans "', V, '" (attendu > >= < <= = !=)');
               Halt(1);
             end;
          3: begin
               WriteLn(ErrOutput, 'Erreur: --fail-if/--warn-if : opérateur inconnu dans "', V, '"');
               Halt(1);
             end;
          4: begin
               WriteLn(ErrOutput, 'Erreur: --fail-if/--warn-if : seuil non numérique dans "', V, '"');
               Halt(1);
             end;
          5: begin
               WriteLn(ErrOutput, 'Erreur: --fail-if/--warn-if : métrique inconnue "', CheckMetric, '"');
               Halt(1);
             end;
        end;
        SetLength(Checks, Length(Checks) + 1);
        with Checks[High(Checks)] do
        begin
          Metric := CheckMetric;      // nom canonique du gate
          Op := CheckOp;
          Threshold := CheckThr;
          IsWarn := IsWarnCheck;
          IsDelta := False;
        end;
      end
      else if (Param = '--fail-on-delta') or (Copy(Param, 1, 15) = '--fail-on-delta=') or
              (Copy(Param, 1, 15) = '--fail-on-delta:') then
      begin
        if (Copy(Param, 1, 15) = '--fail-on-delta=') or (Copy(Param, 1, 15) = '--fail-on-delta:') then
          V := Copy(ParamOrig, 16, Length(ParamOrig))
        else
        begin
          if i >= ParamCount then
          begin
            WriteLn(ErrOutput, 'Erreur: --fail-on-delta : valeur manquante (METRIQUE>X, X en %)');
            Halt(1);
          end;
          Inc(i);
          V := ParamStr(i);
        end;
        // Opérateur '>' imposé : accepté aussi en argument séparé
        // (--fail-on-delta lines > 10)
        if not ContainsCheckOp(V) then
        begin
          if (i < ParamCount) and IsOpToken(ParamStr(i + 1)) then
          begin
            Inc(i);
            OpToken := ParamStr(i);
            if OpToken <> '>' then
            begin
              WriteLn(ErrOutput, 'Erreur: --fail-on-delta : l''opérateur doit être ">" seul (reçu "', OpToken, '")');
              Halt(1);
            end;
            if i >= ParamCount then
            begin
              WriteLn(ErrOutput, 'Erreur: --fail-on-delta : seuil manquant après ">"');
              Halt(1);
            end;
            Inc(i);
            V := V + OpToken + ParamStr(i);
          end;
        end;
        Code := ParseDeltaSpec(V, DeltaMetric, DeltaThr);
        case Code of
          0: ;
          1: begin
               WriteLn(ErrOutput, 'Erreur: --fail-on-delta : opérateur ">" manquant dans "', V, '"');
               Halt(1);
             end;
          2: begin
               WriteLn(ErrOutput, 'Erreur: --fail-on-delta : métrique inconnue "', DeltaMetric, '"');
               Halt(1);
             end;
          3: begin
               WriteLn(ErrOutput, 'Erreur: --fail-on-delta : seuil non numérique dans "', V, '"');
               Halt(1);
             end;
          4: begin
               WriteLn(ErrOutput, 'Erreur: --fail-on-delta : métrique manquante dans "', V, '"');
               Halt(1);
             end;
          5: begin
               WriteLn(ErrOutput, 'Erreur: --fail-on-delta : l''opérateur doit être ">" seul (">=" interdit)');
               Halt(1);
             end;
        end;
        Inc(FailOnDeltaCount);
        SetLength(Checks, Length(Checks) + 1);
        with Checks[High(Checks)] do
        begin
          Metric := DeltaMetric;   // nom canonique (clé du summary-json)
          Op := opGt;
          Threshold := DeltaThr;   // seuil en %
          IsWarn := False;
          IsDelta := True;
        end;
      end

      // Argument non reconnu : fichier littéral, pattern glob, ou stdin
      else
        RawFiles.Add(ParamOrig);
      Inc(i);
    end;

    {=========================================================================
    RÉSOLUTION FINALE DES COULEURS
    =========================================================================}
    // Par défaut : aucune couleur. --color n'active un coloriage minimal des
    // titres de section que si la sortie est réellement une console (jamais
    // dans un pipe ni dans un fichier --out). --no-color reste accepté, c'est
    // simplement l'état par défaut (no-op).
    NoColor := True;
    if OptColor and (OutFileName = '') and StdOutIsConsole then
      NoColor := False;

    {=========================================================================
    VALIDATION DES ARGUMENTS
    =========================================================================}
    // Vérifier qu'au moins un fichier, glob ou répertoire est spécifié
    if (RawFiles.Count = 0) and (RecursiveDirs.Count = 0) then
    begin
      PrintUsage(ErrOutput);
      Halt(1);
    end;

    // Si aucun filtre n'est spécifié, afficher tout par défaut
    if (not OptChar) and (not OptWord) and (not OptLine) and
       (not OptJSON) and (not OptCSV) and (not OptSummaryJSON) then
    begin
      OptChar := True;
      OptWord := True;
      OptLine := True;
    end;

    {=========================================================================
    RÉSOLUTION DES FICHIERS (glob, récursif, stdin)
    =========================================================================}
    // Détecter la demande d'entrée standard (- / --stdin)
    for i := 0 to RawFiles.Count - 1 do
      if RawFiles[i] = '-' then UseStdin := True;

    // Résoudre chaque argument positionnel : glob ou fichier littéral
    for i := 0 to RawFiles.Count - 1 do
    begin
      if RawFiles[i] = '-' then Continue;  // stdin, traité après la résolution
      if ContainsWildcard(RawFiles[i]) then
        ResolveGlobPattern(RawFiles[i], Files)   // erreur fatale si aucun match
      else
        Files.Add(RawFiles[i]);                  // chemin littéral (existant ou non)
    end;

    // Résoudre les --recursive=DIR (filtres include/exclude + max-depth)
    for i := 0 to RecursiveDirs.Count - 1 do
    begin
      if not DirectoryExists(RecursiveDirs[i]) then
      begin
        WriteLn(ErrOutput, 'Erreur: répertoire introuvable - ', RecursiveDirs[i]);
        Halt(1);
      end;
      CollectRecursive(RecursiveDirs[i], IncludePatterns, ExcludePatterns, MaxDepth, Files);
    end;

    // Interdire le mélange stdin + fichiers (erreur fatale, exit 1)
    if UseStdin and (Files.Count > 0) then
    begin
      WriteLn(ErrOutput, 'Erreur: l''entrée standard (-) ne peut pas être mélangée avec des fichiers.');
      Halt(1);
    end;
    if UseStdin then
      Files.Add('stdin');  // Marqueur analysé par AnalyzeStdin

    // Tri lexical déterministe + dédoublonnage (sorties reproductibles en CI)
    if Files.Count > 0 then
    begin
      QuickSortStrList(Files, 0, Files.Count - 1);
      DedupeSorted(Files);
    end;

    // C2 (v2.6.0) : mode check implicite — --fail-if, --warn-if, --compare et
    // --fail-on-delta activent le mode check sans --check explicite.
    CheckMode := OptCheck or (Length(Checks) > 0) or (CompareFile <> '');

    // --fail-on-delta sans --compare : erreur fatale — un check de dérive
    // n'a pas de base de comparaison sans baseline.
    if (FailOnDeltaCount > 0) and (CompareFile = '') then
    begin
      WriteLn(ErrOutput, 'Erreur: --fail-on-delta exige --compare BASELINE (fichier baseline NDJSON)');
      Halt(1);
    end;

    // Lecture de la baseline (--compare) : validée AVANT l'analyse — une
    // baseline illisible ou malformée est une erreur fatale (exit 1).
    if CompareFile <> '' then
      LoadBaseline(CompareFile, Baseline);

    {=========================================================================
    CONFIGURATION DE LA SORTIE (CONSOLE OU FICHIER)
    =========================================================================}
    if OutFileName <> '' then
    begin
      // Sécurité : avec un seul fichier de sortie, au plus un format d'export
      Code := 0;
      if OptJSON then Inc(Code);
      if OptCSV then Inc(Code);
      if OptSummaryJSON then Inc(Code);
      if Code > 1 then
      begin
        WriteLn(ErrOutput, 'Erreur: avec --out, choisissez seulement un format d''export (--json, --csv ou --summary-json).');
        Halt(1);
      end;

      // Gestion des couleurs : désactivées par défaut dans les fichiers
      if not OptColor then
        NoColor := True;

      // Test de création du fichier de sortie (détection précoce des erreurs)
      Assign(TestFile, OutFileName);
      {$I-}  // Désactiver les erreurs d'E/S pour gestion manuelle
      Rewrite(TestFile);
      {$I+}

      if IOResult <> 0 then
      begin
        WriteLn(ErrOutput, 'Erreur: impossible de créer le fichier - ', OutFileName);
        Halt(1);
      end;

      Close(TestFile);

      // Redirection de la sortie standard vers le fichier
      Assign(Output, OutFileName);
      {$I-}
      Rewrite(Output);
      {$I+}

      if IOResult <> 0 then
      begin
        WriteLn(ErrOutput, 'Erreur: impossible de rediriger la sortie vers ', OutFileName);
        Halt(1);
      end;

      // Réappliquer le code page UTF-8 : Assign/Rewrite recrée le fichier Text
      // avec le code page texte par défaut (même protection que stdout/stderr).
      SetTextCodePage(Output, CP_UTF8_LOCAL);
    end;

    { Avertissement : --out avec plusieurs fichiers --csv concatène }
    if (OutFileName <> '') and (Files.Count > 1) and OptCSV then
      WriteLn(ErrOutput, 'Attention: --out avec plusieurs fichiers et --csv concatène les sorties dans le même fichier.');

    {=========================================================================
    DÉTERMINATION DU MODE JSON EFFECTIF
    =========================================================================}
    // jmAuto : 1 fichier = objet unique (rétrocompatible), plusieurs = NDJSON
    if OptJSON and (not JsonModeExplicit) then
    begin
      if Files.Count = 1 then
        JsonMode := jmAuto
      else
        JsonMode := jmNDJSON;
    end;

    {=========================================================================
    BOUCLE PRINCIPALE D'ANALYSE
    =========================================================================}
    TotalFiles := 0; TotalLines := 0; TotalWords := 0;
    TotalChars := 0; TotalSentences := 0;

    // Options structure (C2-B) regroupées pour l'analyse
    SOpts.NGramSize := NGramSize;
    SOpts.TopNgramsLimit := TopNgramsLimit;
    SOpts.StopWordMode := StopWordMode;
    SOpts.HistogramKind := HistogramKindOpt;
    SOpts.CharClasses := OptCharClasses;

    // Totaux agrégés des sections structure (C2-B) : remis à zéro
    for k := 0 to CC_CLASS_COUNT - 1 do TotalCharClasses[k] := 0;
    for k := 0 to 6 do TotalHistCounts[k] := 0;

    for i := 0 to Files.Count - 1 do
    begin
      try
        // Analyse du fichier courant (ou de l'entrée standard)
        if Files[i] = 'stdin' then
          AnalyzeStdin(Stats, OptAll, WordMode, CaseFoldMode, MaxUnique, SOpts)
        else
          AnalyzeFile(Files[i], Stats, OptAll, WordMode, CaseFoldMode, MaxUnique, SOpts);

        // C2 (v2.6.0) : évaluation des checks APRÈS l'analyse, sur les
        // compteurs TStats — le streaming et la mémoire bornée ne sont pas
        // affectés. Le pire statut multi-fichiers est cumulé (fail > warn > ok)
        // quel que soit le format de sortie (les exit codes s'appliquent aussi
        // avec --summary-json et --csv, qui n'ont pas de section checks).
        EvaluateChecks(Stats, Checks, Baseline, CheckResults);
        for k := 0 to High(CheckResults) do
          if CheckResults[k].Status = csFail then HasFail := True
          else if CheckResults[k].Status = csWarn then HasWarn := True;

        // Export selon le format demandé
        if OptSummaryJSON then
          WriteLn(BuildSummaryJSON(Stats, OptLexicalStats, OptReadability))
        else if OptJSON then
        begin
          case JsonMode of
            jmAuto:      ExportJSON(Stats, OptAll, OptLexicalStats, OptReadability, CheckResults);
            jmNDJSON:    WriteLn(BuildJSONCompact(Stats, OptAll, OptLexicalStats, OptReadability, CheckResults));
            jmArray:     JsonParts.Add(BuildJSONCompact(Stats, OptAll, OptLexicalStats, OptReadability, CheckResults));
            jmAggregate:
              begin
                JsonParts.Add(BuildJSONCompact(Stats, OptAll, OptLexicalStats, OptReadability, CheckResults));
                // Totaux cumulés pour l'objet aggregate
                Inc(TotalFiles);
                Inc(TotalLines, Stats.LineCount);
                Inc(TotalWords, Stats.WordCount);
                Inc(TotalChars, Stats.CharCount);
                Inc(TotalSentences, Stats.SentenceCount);
                // C2-B : char_classes et histogramme sommés classe par classe.
                // Les n-grams ne sont PAS agrégés (limitation documentée) ;
                // la lisibilité (C2-C, --readability) ne l'est pas non plus :
                // ses métriques sont des ratios par fichier, présentes par
                // fichier uniquement (pas de clés dans "totals").
                if Stats.CharClassesEnabled then
                  for k := 0 to CC_CLASS_COUNT - 1 do
                    Inc(TotalCharClasses[k], Stats.CharClasses[k]);
                if Stats.HistogramKind <> hkNone then
                  for k := 0 to High(Stats.HistCounts) do
                    Inc(TotalHistCounts[k], Stats.HistCounts[k]);
              end;
          end;
        end
        else if OptCSV then
          ExportCSV(Stats, OptAll, OptLexicalStats, OptReadability, CsvKind)
        else
          PrintStats(Stats, OptChar, OptWord, OptLine, OptAll,
                     OptLexicalStats, OptReadability, TopWordsLimit, TopCharsLimit,
                     CheckResults);

        // Confirmation console de l'écriture, uniquement avec --out et sans
        // --quiet. Écrite sur ErrOutput pour ne jamais polluer le fichier de
        // sortie (la sortie elle-même va dans le fichier, pas sur la console).
        if (OutFileName <> '') and (not OptQuiet) then
        begin
          WriteLn(ErrOutput, 'fstats: ', Files[i], ' -> ', OutFileName);
          Flush(ErrOutput);
        end;

      except
        // Gestion d'erreurs : messages sur stderr, code de retour 1
        on E: EFOpenError do
        begin
          HadError := True;
          if Files[i] = 'stdin' then
            WriteLn(ErrOutput, 'Erreur lors de la lecture de l''entrée standard: ', E.Message)
          else
            WriteLn(ErrOutput, 'Erreur: Fichier inaccessible ou introuvable - ', Files[i]);
        end;
        on E: EInOutError do
        begin
          HadError := True;
          if Files[i] = 'stdin' then
            WriteLn(ErrOutput, 'Erreur lors de la lecture de l''entrée standard: ', E.Message)
          else
            WriteLn(ErrOutput, 'Erreur: Fichier inaccessible ou introuvable - ', Files[i]);
        end;
        on E: Exception do
        begin
          HadError := True;
          WriteLn(ErrOutput, 'Erreur lors du traitement de ', Files[i], ': ', E.Message);
        end;
      end;
    end;

    {=========================================================================
    ÉCRITURE DES FORMATS BUFFERISÉS (array / aggregate)
    =========================================================================}
    if OptJSON then
    begin
      if JsonMode = jmArray then
      begin
        WriteLn('[');
        for i := 0 to JsonParts.Count - 1 do
        begin
          Write('  ', JsonParts[i]);
          if i < JsonParts.Count - 1 then WriteLn(',') else WriteLn;
        end;
        WriteLn(']');
      end
      else if JsonMode = jmAggregate then
      begin
        WriteLn('{');
        WriteLn('  "tool": "fstats",');
        WriteLn('  "version": "', FSTATS_VERSION, '",');
        WriteLn('  "schema_version": "1.0",');
        WriteLn('  "generated": "', JsonEscape(CurrentStamp), '",');
        WriteLn('  "files": [');
        for i := 0 to JsonParts.Count - 1 do
        begin
          Write('    ', JsonParts[i]);
          if i < JsonParts.Count - 1 then WriteLn(',') else WriteLn;
        end;
        WriteLn('  ],');
        WriteLn('  "totals": {');
        WriteLn('    "files": ', TotalFiles, ',');
        WriteLn('    "lines": ', TotalLines, ',');
        WriteLn('    "words": ', TotalWords, ',');
        WriteLn('    "characters": ', TotalChars, ',');
        WriteLn('    "sentences": ', TotalSentences);
        // C2-B : totaux agrégés de char_classes et histogramme (sommés classe
        // par classe). Les n-grams n'apparaissent pas dans totals (limitation
        // documentée : présents par fichier uniquement).
        if OptCharClasses then
        begin
          WriteLn(',');
          WriteLn('    "char_classes": {');
          WriteLn('      "letters": ', TotalCharClasses[CC_LETTERS], ',');
          WriteLn('      "digits": ', TotalCharClasses[CC_DIGITS], ',');
          WriteLn('      "whitespace": ', TotalCharClasses[CC_WHITESPACE], ',');
          WriteLn('      "punctuation": ', TotalCharClasses[CC_PUNCTUATION], ',');
          WriteLn('      "control": ', TotalCharClasses[CC_CONTROL], ',');
          WriteLn('      "other": ', TotalCharClasses[CC_OTHER]);
          WriteLn('    }');
        end;
        if HistogramKindOpt <> hkNone then
        begin
          WriteLn(',');
          WriteLn('    "histogram": {');
          WriteLn('      "metric": "', HistogramName(HistogramKindOpt), '",');
          WriteLn('      "classes": [');
          HistRangesTotal := HistogramRanges(HistogramKindOpt);
          for k := 0 to HistClassCount(HistogramKindOpt) - 1 do
          begin
            if k > 0 then WriteLn(',');
            Write('        {"range": "', HistRangesTotal[k],
                  '", "count": ', TotalHistCounts[k], '}');
          end;
          WriteLn;
          WriteLn('      ]');
          WriteLn('    }');
        end;
        WriteLn('  }');
        WriteLn('}');
      end;
    end;

    {=========================================================================
    NETTOYAGE FINAL
    =========================================================================}
    // Fermer le fichier de sortie si redirection était active
    if OutFileName <> '' then
      Close(Output);

    // Code de retour : 1 si au moins un fichier a échoué, 0 sinon
    if HadError then
      Halt(1);

    // C2 (v2.6.0) : exit codes du mode check — uniquement en mode check avec
    // au moins un check défini (--check seul : analyse normale, exit 0). Le
    // mode analyse garde 0/1 (aucune rupture pour les scripts existants).
    if CheckMode and (Length(Checks) > 0) then
    begin
      if HasFail then
        Halt(2);   // au moins un check échoué (prioritaire)
      if HasWarn then
        Halt(3);   // aucun échec mais au moins un warning
    end;

  finally
    // Libération des ressources (garantie même en cas d'exception)
    JsonParts.Free;
    ExcludePatterns.Free;
    IncludePatterns.Free;
    RecursiveDirs.Free;
    Files.Free;
    RawFiles.Free;
  end;
end.
