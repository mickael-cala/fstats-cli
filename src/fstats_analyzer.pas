{=============================================================================
  fstats_analyzer.pas — analyse principale (AnalyzeData/File/Stdin) et watch C3-D
  =============================================================================}
unit fstats_analyzer;

{$mode objfpc}
{$H+}

interface

uses
  fstats_types, fstats_utf8, fstats_glob, fstats_lex,
  SysUtils, Classes, Generics.Collections, Generics.Defaults
  {$IFDEF MSWINDOWS}, Windows{$ENDIF}
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

procedure InstallWatchHandler;

function IsSmartAbbreviation(const W: string): Boolean;
procedure AnalyzeData(const Path: string; Stream: TStream; out Stats: TStats;
                      OptAll: Boolean; WordMode: TWordMode; CaseFoldMode: TCaseFold;
                      SentenceMode: TSentenceMode; MaxUnique: Int64;
                      const SOpts: TStructureOptions;
                      const LOpts: TLogOptions);
procedure AnalyzeFile(const Path: string; out Stats: TStats; OptAll: Boolean;
                      WordMode: TWordMode; CaseFoldMode: TCaseFold;
                      SentenceMode: TSentenceMode; MaxUnique: Int64;
                      const SOpts: TStructureOptions;
                      const LOpts: TLogOptions);
procedure AnalyzeStdin(out Stats: TStats; OptAll: Boolean;
                       WordMode: TWordMode; CaseFoldMode: TCaseFold;
                       SentenceMode: TSentenceMode; MaxUnique: Int64;
                       const SOpts: TStructureOptions;
                       const LOpts: TLogOptions);
procedure WatchFile(const Path: string; IntervalSec: Integer; OptAll: Boolean;
                    WordMode: TWordMode; CaseFoldMode: TCaseFold;
                    SentenceMode: TSentenceMode; MaxUnique: Int64;
                    const SOpts: TStructureOptions; const LOpts: TLogOptions);

implementation
{=============================================================================
  CIBLE 3-D — WATCH : arrêt propre sur Ctrl+C
  =============================================================================}
{$IFDEF MSWINDOWS}
function CtrlCHandler(dwCtrlType: DWORD): BOOL; stdcall;
begin
  // CTRL_C_EVENT, CTRL_BREAK_EVENT, CTRL_CLOSE_EVENT → arrêt demandé
  WatchStop := True;
  Result := True;
end;

procedure InstallWatchHandler;
begin
  SetConsoleCtrlHandler(@CtrlCHandler, True);
end;
{$ELSE}
procedure SigIntHandler(sig: cint); cdecl;
begin
  WatchStop := True;
end;

procedure InstallWatchHandler;
begin
  FpSignal(SIGINT, @SigIntHandler);
  FpSignal(SIGTERM, @SigIntHandler);
end;
{$ENDIF}

{=============================================================================
  ANALYSE PRINCIPALE - CŒUR DU PROGRAMME
  =============================================================================
  Objectif : Analyser un fichier et remplir la structure TStats
  Performance : Utilisation de dictionnaires hashés pour O(1) par opération
  Sécurité : Gestion robuste des erreurs de lecture, validation UTF-8 stricte
  ============================================================================}

// v2.7.0 : abréviations protégées par --sentence-mode=smart. Liste en
// minuscules — le mot courant est comparé après LowerCase. Chaque motif
// protège un point qui le suit immédiatement : « M. » (mot 'm'), « e.g. »
// (premier point : 'e.' est un préfixe de 'e.g' ; second point : le mot
// courant vaut 'e.g' — le '.' fait partie du mot en mode raw par défaut),
// « www. », « etc. », etc. Les abréviations non reconnues (ex. « art. »)
// clôturent normalement la phrase.
const
  SMART_ABBREVIATIONS: array[0..21] of string = (
    'e.g', 'i.e', 'm', 'mme', 'mlle', 'dr', 'pr', 'st', 'ste', 'etc',
    'mr', 'mrs', 'ms', 'jr', 'sr', 'inc', 'ltd', 'co', 'dept', 'fig',
    'vs', 'www'
  );

// v2.7.0 : test d'abréviation du mode smart — vrai si W est exactement une
// abréviation de la liste, ou si W + '.' est un préfixe d'une abréviation
// (cas « e.g. » / « i.e. » : au premier point W = 'e' et 'e.' est un préfixe
// de 'e.g'). N'utilise que Copy/Length (RTL standard, aucune dépendance).
function IsSmartAbbreviation(const W: string): Boolean;
var
  X: string;
begin
  Result := False;
  for X in SMART_ABBREVIATIONS do
  begin
    if X = W then Exit(True);
    if (Length(X) >= Length(W) + 1) and
       (Copy(X, 1, Length(W) + 1) = W + '.') then Exit(True);
  end;
end;

procedure AnalyzeData(const Path: string; Stream: TStream; out Stats: TStats;
                      OptAll: Boolean; WordMode: TWordMode; CaseFoldMode: TCaseFold;
                      SentenceMode: TSentenceMode; MaxUnique: Int64;
                      const SOpts: TStructureOptions;
                      const LOpts: TLogOptions);
var
  Buffer: array[0..BUF_SIZE - 1] of Byte;
  ReadBytes, Pos, Used, i: Integer;
  Carried, NRead, SeqLen, j: Integer;  // v2.14.1 : zone tampon inter-blocs
  Trunc: Boolean;
  CP: UInt32;
  InWord: Boolean;
  IsWordChar: Boolean;
  CurrentWord, CurrentLine: string;
  LineLen, TotalLen, NonEmpty: Int64;
  LastCPWasCR: Boolean;
  PendingSentence: Boolean;  // Contenu non-blanc depuis le dernier terminateur de phrase
  FirstChar: Boolean;        // Vrai tant que le premier caractère du flux n'est pas consommé (BOM)
  LastCP: UInt32;            // Dernier code point traité (v2.6.1 : détection des décimales 3.14)
  DotPending: Boolean;       // Point précédé d'un chiffre en attente de décision (v2.6.1)
  LastChars: string;         // Fenêtre des 8 derniers caractères du flux (v2.7.0 : règle URL)
  W: string;                 // Mot courant en minuscules (v2.7.0 : test d'abréviation smart)

  // Dictionnaires hashés pour accumulation O(1) - CLÉ DE PERFORMANCE
  CharDict: TCharDict;
  WordDict: TWordDict;
  NGramDict: TNGramDict;     // Comptes des n-grams (C2-B, alloué si NGramSize > 0)
  LineDict: TLineDict;       // Comptes des lignes identiques (C3-A, alloué si TopLinesLimit > 0)
  TagDict: TTagDict;         // Comptes des tags extraits (C3-C, alloué si RegexTag <> '')
  TagPat: TTagPattern;       // Pattern tag parsé (C3-C)
  LineTokens: TStringArray;  // Tokens de la ligne courante (flux n-gram, C2-B)
  SentenceWords: Int64;      // Mots de la phrase courante (words_per_sentence, C2-B)
  PairC: TCharPair;
  PairW: TWordPair;
  Count: Int64;
  MaxLines: Integer;  // 0 = mode --all, sinon limite Top N
  // C3-A : traitement des patterns / top-lignes à chaque fin de ligne
  pi: Integer;               // index de boucle sur les patterns
  LineOcc: Int64;            // occurrences du pattern dans la ligne courante

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

  // Clôture une phrase : compteur + histogramme words_per_sentence (C2-B) +
  // reset du compteur de mots et de l'état PendingSentence. Utilisée par la
  // clôture immédiate (! ? …) et par la clôture différée d'un point
  // (décimales, v2.6.1).
  procedure CloseSentence;
  begin
    Inc(Stats.SentenceCount);
    if SOpts.HistogramKind = hkWordsPerSentence then
      Inc(Stats.HistCounts[HistogramIndex(hkWordsPerSentence, SentenceWords)]);
    SentenceWords := 0;
    PendingSentence := False;
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
  // C3-A : dictionnaire des lignes identiques (top-lines)
  LineDict := nil;
  if LOpts.TopLinesLimit > 0 then
    LineDict := TLineDict.Create;
  // C3-C : dictionnaire des tags + pattern parsé
  TagDict := nil;
  SetLength(TagPat, 0);
  if LOpts.RegexTag <> '' then
  begin
    if not ParseTagPattern(LOpts.RegexTag, TagPat) then
    begin
      CharDict.Free;
      WordDict.Free;
      if NGramDict <> nil then NGramDict.Free;
      if LineDict <> nil then LineDict.Free;
      WriteLn(ErrOutput, 'Erreur: --regex-tag : pattern invalide - ', LOpts.RegexTag);
      Halt(1);
    end;
    TagDict := TTagDict.Create;
  end;

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
  // C3-A : état des sections log
  Stats.TopLinesDupEnabled := LOpts.TopLinesLimit > 0;
  Stats.Redact := LOpts.Redact;
  // C3-B : niveaux de log
  Stats.LogLevelsEnabled := LOpts.LogLevels;
  Stats.FilterLevels := LOpts.FilterLevels;
  for i := Ord(Low(TLogLevel)) to Ord(High(TLogLevel)) do
    Stats.LogLevels[TLogLevel(i)] := 0;
  // C3-C : tags
  Stats.TagsEnabled := LOpts.RegexTag <> '';
  SetLength(Stats.Tags, 0);
  SetLength(Stats.PatternResults, Length(LOpts.Patterns));
  for i := 0 to High(LOpts.Patterns) do
  begin
    Stats.PatternResults[i].Pattern := LOpts.Patterns[i];
    Stats.PatternResults[i].Matches := 0;
    Stats.PatternResults[i].Lines := 0;
  end;
  SetLength(Stats.TopLinesDup, 0);
  SentenceWords := 0;
  SetLength(LineTokens, 0);
  FirstChar := True;
  InWord := False;
  CurrentWord := '';
  LastCPWasCR := False;
  PendingSentence := False;
  LastCP := 0;
  DotPending := False;
  LastChars := '';
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
    Carried := 0;  // v2.14.1 : octets portés du bloc précédent
    repeat
      // v2.14.1 (P2, bug métrique) : lire APRÈS les octets portés. Avant,
      // un caractère multi-octets à cheval sur la frontière du buffer 64 Ko
      // était compté invalid_utf8 (2 faux positifs par caractère coupé) —
      // un fichier UTF-8 valide échouait le gate CI selon son alignement.
      NRead := Stream.Read(Buffer[Carried], BUF_SIZE - Carried);
      ReadBytes := Carried + NRead;
      if (NRead = 0) and (Carried > 0) then
      begin
        // Début de séquence orphelin en fin de fichier : chaque octet restant
        // est réellement invalide (1 par octet, comme une séquence cassée).
        Inc(Stats.InvalidUTF8, Carried);
        Carried := 0;
        Break;
      end;
      Pos := 0;

      // Traitement octet par octet du buffer courant
      while Pos < ReadBytes do
      begin
        // Décodage UTF-8 avec validation stricte
        if not DecodeUTF8(@Buffer[Pos], ReadBytes - Pos, CP, Used) then
        begin
          // v2.14.1 : séquence TRONQUÉE par la fin de bloc ? L'octet de tête
          // annonce plus d'octets qu'il n'en reste ET les octets présents
          // sont des continuations valides -> ce n'est PAS une erreur :
          // sortir du while, les octets seront portés au bloc suivant.
          SeqLen := UTF8SeqLen(Buffer[Pos]);
          Trunc := (SeqLen > 1) and (SeqLen > ReadBytes - Pos);
          if Trunc then
            for j := Pos + 1 to ReadBytes - 1 do
              if (Buffer[j] and $C0) <> $80 then Trunc := False;
          if Trunc then Break;

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

        // v2.6.1 : résolution d'un point en attente (précédé d'un chiffre).
        // Si le caractère suivant est un chiffre, c'est une décimale (3.14) :
        // pas de clôture. Sinon, la phrase se clôture ici (ex. « Version 3. »).
        if DotPending then
        begin
          DotPending := False;
          if (CP < $30) or (CP > $39) then
            CloseSentence;
        end;

        // Comptage des phrases : un terminateur est '.' (U+002E), '!'
        // (U+0021), '?' (U+003F) ou '…' (U+2026). Chaque terminateur rencontré
        // clôt une phrase (le compteur s'incrémente ici). PendingSentence
        // mémorise les caractères non-blancs situés après le dernier
        // terminateur, pour compter l'éventuelle phrase finale en fin de fichier.
        // v2.6.1 : un point précédé d'un chiffre est mis en attente — s'il est
        // suivi d'un chiffre (3.14), il ne clôture PAS la phrase (décimale).
        // v2.7.0 (--sentence-mode=smart) : sémantique figée — identique à
        // basic sauf pour le point '.', traité avant la règle décimale :
        //   1. W := LowerCase(CurrentWord) ; si W est une abréviation de
        //      SMART_ABBREVIATIONS, ou si W + '.' est un préfixe d'une
        //      abréviation (cas « e.g. » / « i.e. » : au premier point
        //      W = 'e' et 'e.' est un préfixe de 'e.g'), le point est AVALÉ
        //      (aucune clôture, pas de DotPending : ni maintenant ni au
        //      caractère suivant) ;
        //   2. sinon, si la fenêtre LastChars (les 8 derniers caractères du
        //      flux) contient '://', le point est avalé (URL, ex.
        //      « https://ex.com ») ;
        //   3. sinon, règle décimale v2.6.1 inchangée (LastCP chiffre ->
        //      DotPending ; sinon CloseSentence).
        // Périmètre (limites assumées, documentées) : les abréviations ne
        // sont reconnues que si le point les suit immédiatement (mot courant
        // = abréviation) ; « www. » sans protocole ne protège que son premier
        // point — les points suivants du domaine (ex. « www.ex.com »)
        // clôturent, faute de '://' dans la fenêtre ; un point qui suit un mot
        // NON reconnu, ni '://' dans la fenêtre (ex. « Bonjour. Ensuite »),
        // clôture normalement — noter que la règle des préfixes s'applique
        // dès que W + '.' est un préfixe d'une abréviation, sans condition
        // sur le caractère suivant (« e. g » avec espace avale donc son
        // point, au même titre que le premier point de « e.g. ») ; '!', '?'
        // et '…' clôturent toujours dans les deux modes.
        // C2-B : l'histogramme words_per_sentence reçoit le nombre de mots de
        // la phrase qui se clôt (0 pour une phrase vide, ex. terminuteurs
        // consécutifs : la somme des classes reste égale à sentences).
        if CP = $2E then
        begin
          if SentenceMode = smSmart then
          begin
            W := LowerCase(CurrentWord);
            if IsSmartAbbreviation(W) or (System.Pos('://', LastChars) > 0) then
            begin
              // Point avalé : aucune clôture, pas de DotPending — la phrase
              // se poursuit sans coupure (décision définitive).
            end
            else if (LastCP >= $30) and (LastCP <= $39) then
              DotPending := True
            else
              CloseSentence;
          end
          else if (LastCP >= $30) and (LastCP <= $39) then
            DotPending := True
          else
            CloseSentence;
        end
        else if (CP = $21) or (CP = $3F) or (CP = $2026) then
          CloseSentence
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
          
          // C3-B : détection du niveau de log sur la ligne courante
          if LOpts.LogLevels then
            Inc(Stats.LogLevels[DetectLogLevel(CurrentLine)]);

          // C3-C : extraction des tags sur la ligne courante
          if TagDict <> nil then
          begin
            ExtractTags(TagPat, CurrentLine, TagDict);
            if (LOpts.TopTagsLimit > 0) and (TagDict.Count > TOPLINES_PRUNE_THRESHOLD) and
               (TagDict.Count > LOpts.TopTagsLimit * 8) then
              PruneTags(TagDict, LOpts.TopTagsLimit);
          end;

          // C3-A : patterns et top-lignes sur la ligne courante (avant reset)
          if Length(LOpts.Patterns) > 0 then
            for pi := 0 to High(LOpts.Patterns) do
            begin
              LineOcc := CountPatternOccurrences(LOpts.Patterns[pi], CurrentLine);
              if LineOcc > 0 then
              begin
                Inc(Stats.PatternResults[pi].Matches, LineOcc);
                Inc(Stats.PatternResults[pi].Lines);
              end;
            end;
          if LineDict <> nil then
          begin
            if LineDict.TryGetValue(CurrentLine, Count) then
              LineDict[CurrentLine] := Count + 1
            else
              LineDict.Add(CurrentLine, 1);
            if (LOpts.TopLinesLimit > 0) and (LineDict.Count > TOPLINES_PRUNE_THRESHOLD) and
               (LineDict.Count > LOpts.TopLinesLimit * 8) then
              PruneTopLines(LineDict, LOpts.TopLinesLimit);
          end;

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

        // Mémorise le caractère précédent (v2.6.1 : décision décimale au point
        // suivant). Le LF ignoré d'un CRLF (Continue ci-dessus) ne l'écrase pas.
        LastCP := CP;
        // v2.7.0 : fenêtre des 8 DERNIERS caractères du flux (règle URL du
        // mode smart). Même convention que LastCP : le LF ignoré d'un CRLF ne
        // l'écrase pas. La garde Length > 8 tronque par la gauche — c'est bien
        // la fin de la fenêtre qui doit rester (Copy(..., 1, 8) garderait les
        // 8 PREMIERS caractères, rendant la règle URL inopérante).
        LastChars := LastChars + VisualChar(CP);
        if Length(LastChars) > 8 then
          LastChars := Copy(LastChars, Length(LastChars) - 7, 8);
      end;
      // v2.14.1 : porter le début de séquence tronqué en tête du prochain
      // bloc (zone tampon). Move est sûr : le décalage va vers l'avant.
      Carried := ReadBytes - Pos;
      if Carried > 0 then
        Move(Buffer[Pos], Buffer[0], Carried);
    until NRead = 0;  // Fin du fichier

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

    // C3-A : patterns et top-lignes sur la dernière ligne (si non vide)
    if LineLen > 0 then
    begin
      // C3-B : niveau de log de la dernière ligne
      if LOpts.LogLevels then
        Inc(Stats.LogLevels[DetectLogLevel(CurrentLine)]);

      // C3-C : tags sur la dernière ligne
      if TagDict <> nil then
        ExtractTags(TagPat, CurrentLine, TagDict);

      if Length(LOpts.Patterns) > 0 then
        for pi := 0 to High(LOpts.Patterns) do
        begin
          LineOcc := CountPatternOccurrences(LOpts.Patterns[pi], CurrentLine);
          if LineOcc > 0 then
          begin
            Inc(Stats.PatternResults[pi].Matches, LineOcc);
            Inc(Stats.PatternResults[pi].Lines);
          end;
        end;
      if LineDict <> nil then
      begin
        if LineDict.TryGetValue(CurrentLine, Count) then
          LineDict[CurrentLine] := Count + 1
        else
          LineDict.Add(CurrentLine, 1);
      end;
    end;

    // v2.6.1 : un point en attente en fin de fichier (ex. « 3.14 » en fin de
    // flux sans caractère suivant) clôt la phrase — même règle que la clôture
    // différée (le point final « 3. » reste une vraie fin de phrase).
    if DotPending then
    begin
      DotPending := False;
      CloseSentence;
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

    // C3-A : conversion du dictionnaire des lignes identiques en top-K
    if LineDict <> nil then
      BuildTopLines(LineDict, LOpts.TopLinesLimit, Stats.TopLinesDup);

    // C3-C : conversion du dictionnaire des tags en top-K
    if TagDict <> nil then
      BuildTags(TagDict, LOpts.TopTagsLimit, Stats.Tags);

  finally
    // Nettoyage obligatoire des ressources (mémoire ; le flux d'entrée est
    // fermé par l'appelant : AnalyzeFile/AnalyzeStdin)
    CharDict.Free;
    WordDict.Free;
    if NGramDict <> nil then NGramDict.Free;
    if LineDict <> nil then LineDict.Free;
    if TagDict <> nil then TagDict.Free;
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
                      WordMode: TWordMode; CaseFoldMode: TCaseFold;
                      SentenceMode: TSentenceMode; MaxUnique: Int64;
                      const SOpts: TStructureOptions;
                      const LOpts: TLogOptions);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    AnalyzeData(Path, FS, Stats, OptAll, WordMode, CaseFoldMode, SentenceMode,
                MaxUnique, SOpts, LOpts);
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
                       WordMode: TWordMode; CaseFoldMode: TCaseFold;
                       SentenceMode: TSentenceMode; MaxUnique: Int64;
                       const SOpts: TStructureOptions;
                       const LOpts: TLogOptions);
var
  HS: THandleStream;
begin
  HS := THandleStream.Create(StdInputHandle);
  try
    AnalyzeData('stdin', HS, Stats, OptAll, WordMode, CaseFoldMode, SentenceMode,
                MaxUnique, SOpts, LOpts);
  finally
    HS.Free;
  end;
end;

{=============================================================================
  CIBLE 3-D — WATCH : surveillance périodique d'un fichier log (polling)
  =============================================================================
  --watch / --follow + --interval=N (défaut 2 s, min 1 s). Boucle infinie :
  à chaque tick, ré-analyse COMPLÈTE du fichier (v1 — l'incrémental octets
  n'est pas implémenté, documenté) et affiche une ligne de statut ASCII :
    [timestamp] lines=N (+delta) words=N chars=N sentences=N [niveaux] size=N
  Le delta est vs le tick précédent. Si le fichier a rétréci (troncature),
  un message "truncated" est affiché (la ré-analyse repart de zéro de toute
  façon). Fichier absent au départ → exit 1. Fichier illisible en cours de
  route → message stderr, on continue. Ctrl+C → arrêt propre, exit 0.
  =============================================================================}
procedure WatchFile(const Path: string; IntervalSec: Integer; OptAll: Boolean;
                    WordMode: TWordMode; CaseFoldMode: TCaseFold;
                    SentenceMode: TSentenceMode; MaxUnique: Int64;
                    const SOpts: TStructureOptions; const LOpts: TLogOptions);
var
  Stats: TStats;
  PrevLines: Int64;  // v2.14.1 : seul le delta lignes est affiche (precedents morts supprimes)
  PrevSize: Int64;
  FirstTick: Boolean;
  CurSize: Int64;
  Delta: Int64;
  S: string;
  Waited, Step: Integer;
begin
  if not FileExists(Path) then
  begin
    WriteLn(ErrOutput, 'Erreur: fichier introuvable pour --watch - ', Path);
    Halt(1);
  end;
  InstallWatchHandler;
  WriteLn('Watching: ', Path, ' (every ', IntervalSec, 's, Ctrl+C to stop)');
  Flush(Output);
  PrevLines := -1;
  PrevSize := -1;
  FirstTick := True;
  while not WatchStop do
  begin
    try
      AnalyzeFile(Path, Stats, OptAll, WordMode, CaseFoldMode, SentenceMode,
                  MaxUnique, SOpts, LOpts);
      CurSize := Stats.CharCount;  // approx : caractères lus = taille approx
      // Taille réelle via FileSize
      // (FileSize renvoie Int64 en FPC 3.2.2 via overload)
      S := '';
      S := S + '[' + CurrentStamp + '] ';
      if FirstTick then
      begin
        S := S + 'lines=' + IntToStr(Stats.LineCount) +
                 ' words=' + IntToStr(Stats.WordCount) +
                 ' chars=' + IntToStr(Stats.CharCount) +
                 ' sentences=' + IntToStr(Stats.SentenceCount);
        FirstTick := False;
      end
      else
      begin
        Delta := Stats.LineCount - PrevLines;
        if Delta >= 0 then
          S := S + 'lines=' + IntToStr(Stats.LineCount) + ' (+' + IntToStr(Delta) + ')'
        else
          S := S + 'lines=' + IntToStr(Stats.LineCount) + ' (' + IntToStr(Delta) + ')';
        S := S + ' words=' + IntToStr(Stats.WordCount) +
                 ' chars=' + IntToStr(Stats.CharCount) +
                 ' sentences=' + IntToStr(Stats.SentenceCount);
      end;
      // Niveaux si --log-level
      if LOpts.LogLevels then
        S := S + ' | error=' + IntToStr(Stats.LogLevels[llError]) +
                 ' warn=' + IntToStr(Stats.LogLevels[llWarn]) +
                 ' info=' + IntToStr(Stats.LogLevels[llInfo]) +
                 ' none=' + IntToStr(Stats.LogLevels[llNone]);
      // Troncature détectée (taille a rétréci)
      if (PrevSize >= 0) and (CurSize < PrevSize) then
        S := S + ' [TRUNCATED]';
      WriteLn(S);
      Flush(Output);
      PrevLines := Stats.LineCount;
      PrevSize := CurSize;
    except
      on E: Exception do
        WriteLn(ErrOutput, '[' + CurrentStamp + '] erreur lecture: ', E.Message);
    end;
    // Sleep par petits pas pour réagir vite au Ctrl+C
    Waited := 0;
    Step := 200;
    while (Waited < IntervalSec * 1000) and (not WatchStop) do
    begin
      Sleep(Step);
      Inc(Waited, Step);
    end;
  end;
  WriteLn('Stopped.');
end;


end.
