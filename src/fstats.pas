{
  ============================================================================
  FSTATS - Analyseur de fichiers statistiques
  ============================================================================
  Auteur     : Expert Free Pascal
  Version    : 2.16.0 (P2 vague 3 : intégrité baseline SHA-256, verdict CI
              lisible, hors-baseline visible, --fail-on-delta inline réparé)
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
  - Log Sentinel (C3-A v2.8.0, C3-B v2.9.0) : --pattern (littéral + | * ?,
    insensible à la casse, occurrences non chevauchantes), --top-lines
    (lignes identiques groupées, top-K borné), --redact=email,ipv4,url
    (*** dans les sorties seulement, compteurs sur le brut),
    --log-level (ERROR>WARN>INFO>DEBUG>TRACE, mot entier), --filter=niveaux
    (filtre l'affichage des lignes, compteurs sur tout le fichier)
  - Checks (Cible 1 B+C) : --check/--fail-if/--warn-if, --compare/
    --fail-on-delta, exit codes 0/1/2/3
  - v2.6.1 : un point entre deux chiffres (3.14) ne clôture plus une phrase
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
  --interactive   : Wizard de génération de la ligne de commande (v2.13.0),
                    compagnon aussi disponible en binaire séparé : fcmd
  
  SÉCURITÉ :
  - Échappement rigoureux des caractères de contrôle en JSON/CSV
  - Gestion d'erreurs sans fuite d'informations sensibles
  - Utilisation de try/finally pour la gestion mémoire
  - Limites connues documentées dans doc/AUDIT-SECURITE.md
    (les anciennes mentions « anti-path traversal » ont été retirées en
    v2.13.1 : aucune fonction ne les implémentait — cf. audit, leçon 4)
  
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
    fstats_types, fstats_utf8, fstats_glob, fstats_lex, fstats_sha,
    fstats_analyzer, fstats_checks, fstats_output, fstats_cmdgen,
    SysUtils, Classes, Windows, Generics.Collections, Generics.Defaults;
{$ELSE}
  // Linux/Mac : pas besoin d'API spécifique, UTF-8 natif
  uses
    fstats_types, fstats_utf8, fstats_glob, fstats_lex, fstats_sha,
    fstats_analyzer, fstats_checks, fstats_output, fstats_cmdgen,
    SysUtils, Classes, BaseUnix, Generics.Collections, Generics.Defaults;
{$ENDIF}



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
  FONCTION PRINCIPALE - POINT D'ENTRÉE
  =============================================================================
  Objectif : Parser les arguments, orchestrer l'analyse, gérer les exports
  Sécurité :
    - Gestion d'erreurs sans fuite d'informations sensibles
    - Redirection propre de la sortie avec gestion des ressources
    - Registre des risques : doc/AUDIT-SECURITE.md
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
  SentenceMode: TSentenceMode; // --sentence-mode (basic par défaut, v2.7.0)
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
  // Cible 3-A : options log (patterns, top-lines, redaction)
  LOpts: TLogOptions;
  Patterns: TStringList;       // --pattern=... (répétable, résolu en LOpts)
  RedactModes: TRedactSet;     // --redact=email,ipv4,url
  // Cible 3-B : niveaux de log
  OptLogLevel: Boolean;        // --log-level
  FilterLevels: TLogLevelSet;  // --filter=ERROR,WARN
  // Cible 3-C : alarm / tags
  RegexTag: string;            // --regex-tag=PATTERN
  // Cible 3-D : watch
  OptWatch: Boolean;           // --watch / --follow
  WatchInterval: Integer;      // --interval=N (défaut 2, min 1)
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
  DeltaCheckCount: Integer;       // checks de dérive définis (v2.16.0)
  MissingBaseline: Integer;        // fichiers sans entrée baseline (v2.16.0)
  ShaActual: string;               // SHA-256 du fichier courant (v2.16.0)
  InBaseline: Boolean;             // fichier présent dans la baseline (v2.16.0)
  ChecksEmitted: Boolean;          // check sha256 injecté sans Checks défini (v2.16.0)
  CheckMetric: string;             // valeurs temporaires de parsing des checks
  CheckOp: TCheckOp;
  CheckThr: Double;
  DeltaMetric: string;
  DeltaThr: Double;
  IsWarnCheck: Boolean;
  OpToken: string;
  CheckLL: TLogLevel;          // valeur temporaire de parsing de --filter
  // v2.13.0 : compagnon --interactive (générateur de ligne de commande)
  WizTokens: TStringList;
  WizCmd: string;
  WizAns: string;
  // v2.14.0 : garde --out (P1-2)
  OutAbs, InAbs: string;
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
  SentenceMode := smBasic;     // v2.7.0 : --sentence-mode, défaut = historique
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
  // Cible 3-A : défauts = sections log désactivées
  TopLinesDupLimit := DEFAULT_TOP_LIMIT;
  RedactModes := [];
  SetLength(LOpts.Patterns, 0);
  LOpts.TopLinesLimit := 0;   // --top-lines non passé = désactivé
  LOpts.Redact := [];
  // Cible 3-B : défauts
  OptLogLevel := False;
  FilterLevels := [];
  LOpts.LogLevels := False;
  LOpts.FilterLevels := [];
  // Cible 3-C : défauts
  RegexTag := '';
  TopTagsLimit := DEFAULT_TOP_LIMIT;
  LOpts.RegexTag := '';
  LOpts.TopTagsLimit := DEFAULT_TOP_LIMIT;
  // Cible 3-D : défauts
  OptWatch := False;
  WatchInterval := 2;
  // C2 (v2.6.0) : défauts du moteur de checks
  OptCheck := False;
  CheckMode := False;
  CompareFile := '';
  SetLength(Checks, 0);
  SetLength(Baseline, 0);
  HasFail := False;
  HasWarn := False;
  FailOnDeltaCount := 0;
  DeltaCheckCount := 0;
  MissingBaseline := 0;
  ChecksEmitted := False;

  OutFileName := '';  // Pas de redirection de sortie par défaut

  // Listes de travail
  RawFiles := TStringList.Create;         // Arguments positionnels (avant résolution)
  Files := TStringList.Create;            // Fichiers résolus (triés, dédoublonnés)
  RecursiveDirs := TStringList.Create;    // --recursive=DIR (répétable)
  IncludePatterns := TStringList.Create;  // --include=PATTERN (répétable)
  ExcludePatterns := TStringList.Create;  // --exclude=PATTERN (répétable)
  JsonParts := TStringList.Create;        // JSON compacts (array/aggregate)
  Patterns := TStringList.Create;          // --pattern=... (C3-A)

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

      // v2.13.0 : compagnon — wizard interactif de génération de commande.
      // Pilotable en pipe ; si l'utilisateur confirme, on se ré-exécute
      // (ParamStr(0) + commande générée) et on propage le exit code.
      else if (Param = '--interactive') or (Param = '--wizard') then
      begin
        WizTokens := TStringList.Create;
        try
          if not RunWizard('fstats', WizTokens, 0) then
            Halt(1);
          Write('Exécuter cette commande ? [o/N] : ');
          if EOF(Input) then
            Halt(0);  // mode non interactif (pipe) : on affiche seulement
          ReadLn(Input, WizAns);
          if LowerCase(Trim(WizAns)) = 'o' then
          begin
            // v2.14.0 (P1-1) : exécution par argv (ExecuteProcess), jamais de
            // shell — le BuildCmd ci-dessous ne sert qu'à l'AFFICHER.
            WizCmd := BuildCmd(ParamStr(0), WizTokens);
            WriteLn('Exécution : ', WizCmd);
            Halt(RunTokens(ParamStr(0), WizTokens));
          end;
          Halt(0);
        finally
          WizTokens.Free;
        end;
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

      // Mode de comptage des phrases (v2.7.0)
      else if (Copy(Param, 1, 16) = '--sentence-mode=') or (Copy(Param, 1, 16) = '--sentence-mode:') then
      begin
        V := LowerCase(Copy(ParamOrig, 17, Length(ParamOrig)));
        if V = 'basic' then SentenceMode := smBasic
        else if V = 'smart' then SentenceMode := smSmart
        else
        begin
          WriteLn(ErrOutput, 'Erreur: --sentence-mode attend "basic" ou "smart" (recu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--sentence-mode' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --sentence-mode=basic|smart');
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

      // Cible 3-A : --pattern=TEXTE (répétable ; aussi --pattern TEXTE)
      else if (Param = '--pattern') or (Copy(Param, 1, 10) = '--pattern=') or
              (Copy(Param, 1, 10) = '--pattern:') then
      begin
        if (Copy(Param, 1, 10) = '--pattern=') or (Copy(Param, 1, 10) = '--pattern:') then
          V := Copy(ParamOrig, 11, Length(ParamOrig))
        else
        begin
          if i >= ParamCount then
          begin
            WriteLn(ErrOutput, 'Erreur: --pattern : valeur manquante (TEXTE)');
            Halt(1);
          end;
          Inc(i);
          V := ParamStr(i);
        end;
        if V = '' then
        begin
          WriteLn(ErrOutput, 'Erreur: --pattern : valeur vide');
          Halt(1);
        end;
        Patterns.Add(V);
      end

      // Cible 3-A : --top-lines=N (0 = désactivé, défaut 10 si --top-lines seul)
      else if (Param = '--top-lines') or (Copy(Param, 1, 12) = '--top-lines=') or
              (Copy(Param, 1, 12) = '--top-lines:') then
      begin
        if (Copy(Param, 1, 12) = '--top-lines=') or (Copy(Param, 1, 12) = '--top-lines:') then
          V := Copy(ParamOrig, 13, Length(ParamOrig))
        else
        begin
          if i >= ParamCount then
            V := IntToStr(DEFAULT_TOP_LIMIT)
          else
          begin
            Inc(i);
            V := ParamStr(i);
          end;
        end;
        Val(V, TopLinesDupLimit, Code);
        if (Code <> 0) or (TopLinesDupLimit < 0) then
        begin
          WriteLn(ErrOutput, 'Erreur: --top-lines attend un entier >= 0 (reçu "', V, '")');
          Halt(1);
        end;
        LOpts.TopLinesLimit := TopLinesDupLimit;
      end

      // Cible 3-A : --redact=email,ipv4,url (séparés par virgule, répétable)
      else if (Copy(Param, 1, 9) = '--redact=') or (Copy(Param, 1, 9) = '--redact:') then
      begin
        V := LowerCase(Copy(ParamOrig, 10, Length(ParamOrig)));
        while V <> '' do
        begin
          k := Pos(',', V);
          if k > 0 then
          begin
            if Copy(V, 1, k - 1) = 'email' then RedactModes := RedactModes + [rmEmail]
            else if Copy(V, 1, k - 1) = 'ipv4' then RedactModes := RedactModes + [rmIPv4]
            else if Copy(V, 1, k - 1) = 'url' then RedactModes := RedactModes + [rmURL]
            else
            begin
              WriteLn(ErrOutput, 'Erreur: --redact attend "email", "ipv4" ou "url" (reçu "', Copy(V, 1, k - 1), '")');
              Halt(1);
            end;
            V := Copy(V, k + 1, Length(V));
          end
          else
          begin
            if V = 'email' then RedactModes := RedactModes + [rmEmail]
            else if V = 'ipv4' then RedactModes := RedactModes + [rmIPv4]
            else if V = 'url' then RedactModes := RedactModes + [rmURL]
            else if V <> '' then
            begin
              WriteLn(ErrOutput, 'Erreur: --redact attend "email", "ipv4" ou "url" (reçu "', V, '")');
              Halt(1);
            end;
            V := '';
          end;
        end;
        LOpts.Redact := RedactModes;
      end

      // Cible 3-B : --log-level (flag)
      else if Param = '--log-level' then
      begin
        OptLogLevel := True;
        LOpts.LogLevels := True;
      end

      // Cible 3-B : --filter=ERROR,WARN,INFO,... (séparés par virgule)
      else if (Copy(Param, 1, 9) = '--filter=') or (Copy(Param, 1, 9) = '--filter:') then
      begin
        V := LowerCase(Copy(ParamOrig, 10, Length(ParamOrig)));
        while V <> '' do
        begin
          k := Pos(',', V);
          if k > 0 then
          begin
            if not ParseLogLevelName(Copy(V, 1, k - 1), CheckLL) then
            begin
              WriteLn(ErrOutput, 'Erreur: --filter attend "error", "warn", "info", "debug", "trace" ou "none" (reçu "', Copy(V, 1, k - 1), '")');
              Halt(1);
            end;
            FilterLevels := FilterLevels + [CheckLL];
            V := Copy(V, k + 1, Length(V));
          end
          else
          begin
            if V <> '' then
            begin
              if not ParseLogLevelName(V, CheckLL) then
              begin
                WriteLn(ErrOutput, 'Erreur: --filter attend "error", "warn", "info", "debug", "trace" ou "none" (reçu "', V, '")');
                Halt(1);
              end;
              FilterLevels := FilterLevels + [CheckLL];
            end;
            V := '';
          end;
        end;
        LOpts.FilterLevels := FilterLevels;
      end

      // Cible 3-C : --regex-tag=PATTERN (mini-moteur : littéral + [classes] + ? * +)
      else if (Copy(Param, 1, 12) = '--regex-tag=') or (Copy(Param, 1, 12) = '--regex-tag:') then
      begin
        V := Copy(ParamOrig, 13, Length(ParamOrig));
        if V = '' then
        begin
          WriteLn(ErrOutput, 'Erreur: --regex-tag : pattern vide');
          Halt(1);
        end;
        RegexTag := V;
      end
      else if Param = '--regex-tag' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --regex-tag=PATTERN');
        Halt(1);
      end

      // Cible 3-C : --top-tags=N (borne du top des tags, défaut 10, 0 = tous)
      else if (Copy(Param, 1, 11) = '--top-tags=') or (Copy(Param, 1, 11) = '--top-tags:') then
      begin
        V := Copy(ParamOrig, 12, Length(ParamOrig));
        Val(V, TopTagsLimit, Code);
        if (Code <> 0) or (TopTagsLimit < 0) then
        begin
          WriteLn(ErrOutput, 'Erreur: --top-tags attend un entier >= 0 (reçu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--top-tags' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --top-tags=N (0 = tous)');
        Halt(1);
      end

      // Cible 3-C : --mode=alarm (raccourci = --log-level + --top-lines + --regex-tag)
      else if (Param = '--mode=alarm') or (Param = '--mode:alarm') then
      begin
        OptLogLevel := True;
        if LOpts.TopLinesLimit = 0 then
        begin
          TopLinesDupLimit := DEFAULT_TOP_LIMIT;
          LOpts.TopLinesLimit := DEFAULT_TOP_LIMIT;
        end;
        if RegexTag = '' then
          RegexTag := '[A-Z]+[0-9]+';  // défaut : identifiants type TAG123, PLC1
      end
      else if Copy(Param, 1, 7) = '--mode=' then
      begin
        WriteLn(ErrOutput, 'Erreur: --mode attend "alarm" (reçu "', Copy(ParamOrig, 8, Length(ParamOrig)), '")');
        Halt(1);
      end

      // Cible 3-D : --watch / --follow (surveillance périodique)
      else if (Param = '--watch') or (Param = '--follow') then
        OptWatch := True

      // Cible 3-D : --interval=N (secondes, défaut 2, min 1)
      else if (Copy(Param, 1, 11) = '--interval=') or (Copy(Param, 1, 11) = '--interval:') then
      begin
        V := Copy(ParamOrig, 12, Length(ParamOrig));
        Val(V, WatchInterval, Code);
        if (Code <> 0) or (WatchInterval < 1) then
        begin
          WriteLn(ErrOutput, 'Erreur: --interval attend un entier >= 1 (reçu "', V, '")');
          Halt(1);
        end;
      end
      else if Param = '--interval' then
      begin
        WriteLn(ErrOutput, 'Erreur: utilisez --interval=N (secondes, min 1)');
        Halt(1);
      end

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
      else if (Param = '--fail-on-delta') or (Copy(Param, 1, 16) = '--fail-on-delta=') or
              (Copy(Param, 1, 16) = '--fail-on-delta:') then
      begin
        if (Copy(Param, 1, 16) = '--fail-on-delta=') or (Copy(Param, 1, 16) = '--fail-on-delta:') then
          V := Copy(ParamOrig, 17, Length(ParamOrig))
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

    // Cible 3-D : --watch exige exactement 1 fichier, pas de stdin
    if OptWatch then
    begin
      if UseStdin then
      begin
        WriteLn(ErrOutput, 'Erreur: --watch ne fonctionne pas avec l''entrée standard (-).');
        Halt(1);
      end;
      if Files.Count <> 1 then
      begin
        WriteLn(ErrOutput, 'Erreur: --watch attend exactement UN fichier (reçu ', Files.Count, ').');
        Halt(1);
      end;
      SOpts.NGramSize := NGramSize;
      SOpts.TopNgramsLimit := TopNgramsLimit;
      SOpts.StopWordMode := StopWordMode;
      SOpts.HistogramKind := HistogramKindOpt;
      SOpts.CharClasses := OptCharClasses;
      SetLength(LOpts.Patterns, Patterns.Count);
      for k := 0 to Patterns.Count - 1 do
        LOpts.Patterns[k] := Patterns[k];
      LOpts.TopLinesLimit := TopLinesDupLimit;
      LOpts.Redact := RedactModes;
      LOpts.LogLevels := OptLogLevel;
      LOpts.FilterLevels := FilterLevels;
      LOpts.RegexTag := RegexTag;
      LOpts.TopTagsLimit := TopTagsLimit;
      WatchFile(Files[0], WatchInterval, OptAll, WordMode, CaseFoldMode,
                SentenceMode, MaxUnique, SOpts, LOpts);
      Halt(0);
    end;

    // C2 (v2.6.0) : mode check implicite — --fail-if, --warn-if, --compare et
    // --fail-on-delta activent le mode check sans --check explicite.
    CheckMode := OptCheck or (Length(Checks) > 0) or (CompareFile <> '');

    // v2.16.0 (P2 vague 3) : nombre de checks de dérive — conditionne le
    // signalement des fichiers absents de la baseline.
    DeltaCheckCount := 0;
    for k := 0 to High(Checks) do
      if Checks[k].IsDelta then
        Inc(DeltaCheckCount);

    // v2.14.1 (P2) : un gate no-op doit être VISIBLE. Sans check défini,
    // le mode check rend toujours exit 0 sans rien tester — footgun CI.
    // Avertissement stderr uniquement (comportement/exit inchangés).
    if CheckMode and (Length(Checks) = 0) then
      WriteLn(ErrOutput, 'Attention: mode check actif sans aucun check defini ',
              '(--fail-if / --warn-if / --fail-on-delta) : le gate ne teste rien.',
              ' Ajoutez au moins un check ou retirez --check.');

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

      // v2.14.0 (P1-2, audit sécurité) : refuser que --out désigne un fichier
      // analysé — Rewrite tronque AVANT l'analyse, ce qui détruisait l'entrée
      // (fstats f.txt --out=f.txt vidait f.txt de façon irréversible).
      OutAbs := ExpandFileName(OutFileName);
      for k := 0 to Files.Count - 1 do
      begin
        InAbs := ExpandFileName(Files[k]);
        {$IFDEF MSWINDOWS}
        if LowerCase(OutAbs) = LowerCase(InAbs) then
        {$ELSE}
        if OutAbs = InAbs then
        {$ENDIF}
        begin
          WriteLn(ErrOutput, 'Erreur: --out (', OutFileName, ') designe un fichier analyse (',
                  Files[k], ') - refus pour eviter sa destruction.');
          Halt(1);
        end;
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
    // Cible 3-A : options log regroupées pour l'analyse
    SetLength(LOpts.Patterns, Patterns.Count);
    for k := 0 to Patterns.Count - 1 do
      LOpts.Patterns[k] := Patterns[k];
    LOpts.TopLinesLimit := TopLinesDupLimit;
    LOpts.Redact := RedactModes;
    LOpts.LogLevels := OptLogLevel;
    LOpts.FilterLevels := FilterLevels;
    LOpts.RegexTag := RegexTag;
    LOpts.TopTagsLimit := TopTagsLimit;

    // Totaux agrégés des sections structure (C2-B) : remis à zéro
    for k := 0 to CC_CLASS_COUNT - 1 do TotalCharClasses[k] := 0;
    for k := 0 to 6 do TotalHistCounts[k] := 0;

    for i := 0 to Files.Count - 1 do
    begin
      try
        // Analyse du fichier courant (ou de l'entrée standard)
        if Files[i] = 'stdin' then
          AnalyzeStdin(Stats, OptAll, WordMode, CaseFoldMode, SentenceMode, MaxUnique, SOpts, LOpts)
        else
          AnalyzeFile(Files[i], Stats, OptAll, WordMode, CaseFoldMode, SentenceMode,
                      MaxUnique, SOpts, LOpts);

        // v2.16.0 (P2 vague 3) : SHA-256 du contenu (streaming, mémoire
        // bornée) — clé "sha256" du summary-json ET vérification d'intégrité
        // au --compare. stdin et fichier illisible : pas de hash ('').
        if Files[i] = 'stdin' then
          ShaActual := ''
        else
          ShaActual := FileSHA256(Files[i]);

        // C2 (v2.6.0) : évaluation des checks APRÈS l'analyse, sur les
        // compteurs TStats — le streaming et la mémoire bornée ne sont pas
        // affectés. Le pire statut multi-fichiers est cumulé (fail > warn > ok)
        // quel que soit le format de sortie (les exit codes s'appliquent aussi
        // avec --summary-json et --csv, qui n'ont pas de section checks).
        EvaluateChecks(Stats, Checks, Baseline, ShaActual, CheckResults);
        // v2.16.0 : un check sha256 peut être émis SANS aucun --fail-if
        // (baseline avec clé sha256) — il compte pour la gate et le verdict.
        if Length(CheckResults) > 0 then
          ChecksEmitted := True;

        // v2.16.0 (P2 vague 3) : un fichier absent de la baseline n'est plus
        // IGNORE en silence — avertissement stderr + compteur (visible dans
        // le verdict console). Comportement/exit inchangés.
        if CheckMode and (DeltaCheckCount > 0) and (CompareFile <> '') then
        begin
          InBaseline := False;
          for k := 0 to High(Baseline) do
            if Baseline[k].FilePath = Stats.Path then
            begin
              InBaseline := True;
              Break;
            end;
          if not InBaseline then
          begin
            Inc(MissingBaseline);
            WriteLn(ErrOutput, 'Attention: ', Stats.Path, ' absent de la baseline ',
                    '(--compare) : checks de derive ignores pour ce fichier.');
            Flush(ErrOutput);
          end;
        end;
        for k := 0 to High(CheckResults) do
          if CheckResults[k].Status = csFail then HasFail := True
          else if CheckResults[k].Status = csWarn then HasWarn := True;

        // Export selon le format demandé
        if OptSummaryJSON then
          WriteLn(BuildSummaryJSON(Stats, OptLexicalStats, OptReadability, ShaActual))
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

    // v2.16.0 (P2 vague 3) : verdict final LIISIBLE en mode check console —
    // la dernière ligne du gate dit ce qui s'est passé, au lieu de laisser
    // le lecteur déduire de l'exit code. Uniquement sur la sortie console
    // (jamais dans --json/--csv/--summary-json : les formats de données
    // restent purs, les exit codes font foi pour les scripts).
    if CheckMode and ((Length(Checks) > 0) or ChecksEmitted) and
       (not OptSummaryJSON) and (not OptJSON) and (not OptCSV) then
    begin
      if HasFail then
        WriteLn('Verdict : ECHEC (au moins un check --fail-if en echec) - exit 2')
      else if HasWarn then
        WriteLn('Verdict : ATTENTION (au moins un --warn-if declenche, aucun echec) - exit 3')
      else
        WriteLn('Verdict : OK (tous les checks passent) - exit 0');
      if MissingBaseline > 0 then
        WriteLn('  ', MissingBaseline, ' fichier(s) hors baseline : checks de derive ignores');
    end;

    // Code de retour : 1 si au moins un fichier a échoué, 0 sinon
    if HadError then
      Halt(1);

    // C2 (v2.6.0) : exit codes du mode check — uniquement en mode check avec
    // au moins un check défini OU un check sha256 émis (v2.16.0). --check
    // seul (nothing) : analyse normale, exit 0. Le mode analyse garde 0/1
    // (aucune rupture pour les scripts existants).
    if CheckMode and ((Length(Checks) > 0) or ChecksEmitted) then
    begin
      if HasFail then
        Halt(2);   // au moins un check échoué (prioritaire)
      if HasWarn then
        Halt(3);   // aucun échec mais au moins un warning
    end;

  finally
    // Libération des ressources (garantie même en cas d'exception)
    JsonParts.Free;
    Patterns.Free;
    ExcludePatterns.Free;
    IncludePatterns.Free;
    RecursiveDirs.Free;
    Files.Free;
    RawFiles.Free;
  end;
end.
