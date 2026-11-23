{=============================================================================
  fstats_output.pas — stats lexicales/lisibilite, sortie console, JSON, CSV, usage
  =============================================================================}
unit fstats_output;

{$mode objfpc}
{$H+}

interface

uses
  fstats_types, fstats_utf8, fstats_glob, fstats_lex, fstats_checks,
  SysUtils, Classes, Generics.Collections, Generics.Defaults;

function EffectiveLimit(Total: Integer; ShowAll: Boolean; TopLimit: Integer): Integer;
function ComputeLexical(const Stats: TStats): TLexicalStats;
function ComputeReadability(const Stats: TStats): TReadabilityStats;
function SummaryLine(const Label_: string; Value: Int64): string;
function SummaryLineText(const Label_: string; const Value: string): string;
function SectionTitle(const Name: string; Limit, Total: Integer): string;
procedure PrintStats(const Stats: TStats; ShowChars, ShowWords, ShowLines, ShowAll: Boolean;
                     LexicalStats: Boolean; Readability: Boolean;
                     TopWordsLimit, TopCharsLimit: Integer;
                     const CheckResults: TCheckResultArray);
function JsonEscape(const S: string): string;
procedure ExportJSON(const Stats: TStats; ShowAll: Boolean; LexicalStats: Boolean;
                    Readability: Boolean; const CheckResults: TCheckResultArray);
function BoolToJSON(B: Boolean): string;
function BuildTopCharsJSON(const Stats: TStats; ShowAll: Boolean; TopLimit: Integer): string;
function BuildTopWordsJSON(const Stats: TStats; ShowAll: Boolean; TopLimit: Integer): string;
function BuildTopLinesJSON(const Stats: TStats; ShowAll: Boolean): string;
function BuildTopLinesJSONRedact(const Stats: TStats; ShowAll: Boolean): string;
function BuildHistogramJSON(const Stats: TStats): string;
function BuildNGramsJSON(const Stats: TStats; ShowAll: Boolean; TopK: Integer): string;
function BuildJSONCompact(const Stats: TStats; ShowAll: Boolean; LexicalStats: Boolean;
                          Readability: Boolean;
                          const CheckResults: TCheckResultArray): string;
function BuildSummaryJSON(const Stats: TStats; LexicalStats: Boolean;
                          Readability: Boolean): string;
function CsvEscape(const S: string): string;
procedure ExportCSV(const Stats: TStats; ShowAll: Boolean; LexicalStats: Boolean;
                    Readability: Boolean; CsvKind: TCsvKind);
procedure PrintUsage(var Out: Text);

implementation

{=============================================================================
  STATISTIQUES LEXICALES (incrément C2-A) — calcul et formatage
  =============================================================================
  --lexical-stats ajoute : unique_words, hapax, type_token_ratio,
  average_word_length, entropy_bits_per_word. Formules figées dans le README
  (« Sémantique lexicale »).
  =============================================================================}

{----------------------------------------------------------------------------
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
  i, j, Limit, Total, RankW: Integer;
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

    j := 0;  // compteur de lignes affichées (renumérotation si filtre C3-B)
    for i := 0 to Limit - 1 do
    begin
      { C3-B : filtre par niveau (affichage seulement, compteurs sur le brut) }
      if (Stats.FilterLevels <> []) and
         (not (DetectLogLevel(Stats.TopLines[i].Text) in Stats.FilterLevels)) then
        Continue;
      Inc(j);
      Preview := Stats.TopLines[i].Text;
      { C3-A : redaction appliquée aux sorties seulement }
      if Stats.Redact <> [] then
        Preview := RedactString(Preview, Stats.Redact);
      { Préview tronquée à ~60 caractères UTF-8 sans couper une séquence
        multi-octets (UTF8SafeCopy), suffixée de "..." si tronquée }
      if UTF8Length(Preview) > 60 then
        Preview := UTF8SafeCopy(Preview, 57) + '...';
      WriteLn('  ', j:RankW, '  ',
              Format('%6d', [Stats.TopLines[i].Len]), '  ',
              Preview);
    end;
    WriteLn;
  end;

  { Section Patterns (C3-A) — affichée si au moins un --pattern est défini.
    Rang, pattern, nombre de lignes matchées et nombre total d'occurrences. }
  if Length(Stats.PatternResults) > 0 then
  begin
    Title := 'Patterns';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn('  ', UTF8PadRight('Pattern', 24), '  ', 'Lines', '  ', 'Matches');
    for i := 0 to High(Stats.PatternResults) do
      WriteLn('  ', UTF8PadRight(QuotedStr(Stats.PatternResults[i].Pattern), 24), '  ',
              Format('%5d', [Stats.PatternResults[i].Lines]), '  ',
              Format('%7d', [Stats.PatternResults[i].Matches]));
    WriteLn;
  end;

  { Section Top Lines (C3-A) — lignes identiques les plus fréquentes (--top-lines).
    Redaction appliquée à l'exemple affiché. }
  if Stats.TopLinesDupEnabled and (Length(Stats.TopLinesDup) > 0) then
  begin
    Title := SectionTitle('Top Lines', EffectiveLimit(Length(Stats.TopLinesDup), ShowAll, TopLinesDupLimit),
                          Length(Stats.TopLinesDup));
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn('  #  Count  Line');
    Limit := EffectiveLimit(Length(Stats.TopLinesDup), ShowAll, TopLinesDupLimit);
    j := 0;
    for i := 0 to Limit - 1 do
    begin
      { C3-B : filtre par niveau }
      if (Stats.FilterLevels <> []) and
         (not (DetectLogLevel(Stats.TopLinesDup[i].Line) in Stats.FilterLevels)) then
        Continue;
      Inc(j);
      Preview := Stats.TopLinesDup[i].Line;
      if Stats.Redact <> [] then
        Preview := RedactString(Preview, Stats.Redact);
      if UTF8Length(Preview) > 60 then
        Preview := UTF8SafeCopy(Preview, 57) + '...';
      WriteLn('  ', j:2, '  ', Format('%5d', [Stats.TopLinesDup[i].Count]), '  ', Preview);
    end;
    WriteLn;
  end;

  { Section Log Levels (C3-B) — affichée avec --log-level. Somme = lines. }
  if Stats.LogLevelsEnabled then
  begin
    Title := 'Log Levels';
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn(SummaryLine('Error:', Stats.LogLevels[llError]));
    WriteLn(SummaryLine('Warn:', Stats.LogLevels[llWarn]));
    WriteLn(SummaryLine('Info:', Stats.LogLevels[llInfo]));
    WriteLn(SummaryLine('Debug:', Stats.LogLevels[llDebug]));
    WriteLn(SummaryLine('Trace:', Stats.LogLevels[llTrace]));
    WriteLn(SummaryLine('None:', Stats.LogLevels[llNone]));
    WriteLn;
  end;

  { Section Tags (C3-C) — affichée avec --regex-tag / --mode=alarm. }
  if Stats.TagsEnabled and (Length(Stats.Tags) > 0) then
  begin
    Title := SectionTitle('Tags', EffectiveLimit(Length(Stats.Tags), ShowAll, TopTagsLimit),
                          Length(Stats.Tags));
    WriteLn(AnsiColor(36), Title, AnsiReset);
    WriteLn(RepeatString('-', Length(Title)));
    WriteLn('  #  Count  Tag');
    Limit := EffectiveLimit(Length(Stats.Tags), ShowAll, TopTagsLimit);
    for i := 0 to Limit - 1 do
      WriteLn('  ', i + 1:2, '  ', Format('%5d', [Stats.Tags[i].Count]), '  ',
              Stats.Tags[i].Tag);
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

  // C3-A : bloc patterns (si au moins un --pattern) — inséré avant longest_lines
  if Length(Stats.PatternResults) > 0 then
  begin
    WriteLn('  "patterns": [');
    for i := 0 to High(Stats.PatternResults) do
    begin
      if i > 0 then WriteLn(',');
      Write('    {"pattern": "', JsonEscape(Stats.PatternResults[i].Pattern),
            '", "lines": ', Stats.PatternResults[i].Lines,
            ', "matches": ', Stats.PatternResults[i].Matches, '}');
    end;
    WriteLn;
    WriteLn('  ],');
  end;

  // C3-A : bloc top_lines (lignes identiques, --top-lines)
  if Stats.TopLinesDupEnabled and (Length(Stats.TopLinesDup) > 0) then
  begin
    WriteLn('  "top_lines": [');
    Limit := EffectiveLimit(Length(Stats.TopLinesDup), ShowAll, TopLinesDupLimit) - 1;
    for i := 0 to Limit do
    begin
      if i > 0 then WriteLn(',');
      Write('    {"rank": ', i + 1, ', "count": ', Stats.TopLinesDup[i].Count, ', "line": "');
      if Stats.Redact <> [] then
        Write(JsonEscape(RedactString(Stats.TopLinesDup[i].Line, Stats.Redact)))
      else
        Write(JsonEscape(Stats.TopLinesDup[i].Line));
      Write('"}');
    end;
    WriteLn;
    WriteLn('  ],');
  end;

  // C3-B : bloc log_levels (--log-level)
  if Stats.LogLevelsEnabled then
  begin
    WriteLn('  "log_levels": {');
    WriteLn('    "error": ', Stats.LogLevels[llError], ',');
    WriteLn('    "warn": ', Stats.LogLevels[llWarn], ',');
    WriteLn('    "info": ', Stats.LogLevels[llInfo], ',');
    WriteLn('    "debug": ', Stats.LogLevels[llDebug], ',');
    WriteLn('    "trace": ', Stats.LogLevels[llTrace], ',');
    WriteLn('    "none": ', Stats.LogLevels[llNone]);
    WriteLn('  },');
  end;

  // C3-C : bloc tags (--regex-tag / --mode=alarm)
  if Stats.TagsEnabled and (Length(Stats.Tags) > 0) then
  begin
    WriteLn('  "tags": [');
    Limit := EffectiveLimit(Length(Stats.Tags), ShowAll, TopTagsLimit) - 1;
    for i := 0 to Limit do
    begin
      if i > 0 then WriteLn(',');
      Write('    {"rank": ', i + 1, ', "tag": "', JsonEscape(Stats.Tags[i].Tag),
            '", "count": ', Stats.Tags[i].Count, '}');
    end;
    WriteLn;
    WriteLn('  ],');
  end;

  // Longest Lines (C3-A : redaction appliquée au contenu exporté) — DERNIER bloc, pas de virgule
  Write('  "longest_lines": [');
  Limit := EffectiveLimit(Length(Stats.TopLines), ShowAll, DEFAULT_TOP_LIMIT) - 1;
  for i := 0 to Limit do
  begin
    if i > 0 then Write(',');
    WriteLn;
    Write('    {"rank": ', i+1, ', ');
    Write('"length": ', Stats.TopLines[i].Len, ', ');
    if Stats.Redact <> [] then
      Write('"content": "', JsonEscape(RedactString(Stats.TopLines[i].Text, Stats.Redact)), '"}')
    else
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
  BuildTopLinesJSONRedact : Comme BuildTopLinesJSON mais applique la redaction
  C3-A au contenu de chaque ligne si Stats.Redact <> [].
  -----------------------------------------------------------------------------}
function BuildTopLinesJSONRedact(const Stats: TStats; ShowAll: Boolean): string;
var
  i, Limit: Integer;
  Content: string;
begin
  Limit := EffectiveLimit(Length(Stats.TopLines), ShowAll, DEFAULT_TOP_LIMIT) - 1;
  Result := '[';
  for i := 0 to Limit do
  begin
    if i > 0 then Result := Result + ',';
    Content := Stats.TopLines[i].Text;
    if Stats.Redact <> [] then
      Content := RedactString(Content, Stats.Redact);
    Result := Result + '{"rank": ' + IntToStr(i + 1) +
      ', "length": ' + IntToStr(Stats.TopLines[i].Len) +
      ', "content": "' + JsonEscape(Content) + '"}';
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
  i, Limit: Integer;
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
  // C3-A : blocs patterns et top_lines (avant longest_lines)
  if Length(Stats.PatternResults) > 0 then
  begin
    S := S + ', "patterns": [';
    for i := 0 to High(Stats.PatternResults) do
    begin
      if i > 0 then S := S + ',';
      S := S + '{"pattern": "' + JsonEscape(Stats.PatternResults[i].Pattern) +
        '", "lines": ' + IntToStr(Stats.PatternResults[i].Lines) +
        ', "matches": ' + IntToStr(Stats.PatternResults[i].Matches) + '}';
    end;
    S := S + ']';
  end;
  if Stats.TopLinesDupEnabled and (Length(Stats.TopLinesDup) > 0) then
  begin
    S := S + ', "top_lines": [';
    Limit := EffectiveLimit(Length(Stats.TopLinesDup), ShowAll, TopLinesDupLimit) - 1;
    for i := 0 to Limit do
    begin
      if i > 0 then S := S + ',';
      S := S + '{"rank": ' + IntToStr(i + 1) +
        ', "count": ' + IntToStr(Stats.TopLinesDup[i].Count) +
        ', "line": "';
      if Stats.Redact <> [] then
        S := S + JsonEscape(RedactString(Stats.TopLinesDup[i].Line, Stats.Redact))
      else
        S := S + JsonEscape(Stats.TopLinesDup[i].Line);
      S := S + '"}';
    end;
    S := S + ']';
  end;
  // C3-B : bloc log_levels
  if Stats.LogLevelsEnabled then
  begin
    S := S + ', "log_levels": {"error": ' + IntToStr(Stats.LogLevels[llError]) +
      ', "warn": ' + IntToStr(Stats.LogLevels[llWarn]) +
      ', "info": ' + IntToStr(Stats.LogLevels[llInfo]) +
      ', "debug": ' + IntToStr(Stats.LogLevels[llDebug]) +
      ', "trace": ' + IntToStr(Stats.LogLevels[llTrace]) +
      ', "none": ' + IntToStr(Stats.LogLevels[llNone]) + '}';
  end;
  // C3-C : bloc tags
  if Stats.TagsEnabled and (Length(Stats.Tags) > 0) then
  begin
    S := S + ', "tags": [';
    Limit := EffectiveLimit(Length(Stats.Tags), ShowAll, TopTagsLimit) - 1;
    for i := 0 to Limit do
    begin
      if i > 0 then S := S + ',';
      S := S + '{"rank": ' + IntToStr(i + 1) + ', "tag": "' + JsonEscape(Stats.Tags[i].Tag) +
        '", "count": ' + IntToStr(Stats.Tags[i].Count) + '}';
    end;
    S := S + ']';
  end;
  // C3-A : redaction dans longest_lines
  S := S + ', "longest_lines": ' + BuildTopLinesJSONRedact(Stats, ShowAll);
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
  i: Integer;
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
  // C3-A : patterns et top_lines en clés plates (tableaux JSON compacts)
  if Length(Stats.PatternResults) > 0 then
  begin
    S := S + ', "patterns": [';
    for i := 0 to High(Stats.PatternResults) do
    begin
      if i > 0 then S := S + ',';
      S := S + '{"pattern": "' + JsonEscape(Stats.PatternResults[i].Pattern) +
        '", "lines": ' + IntToStr(Stats.PatternResults[i].Lines) +
        ', "matches": ' + IntToStr(Stats.PatternResults[i].Matches) + '}';
    end;
    S := S + ']';
  end;
  if Stats.TopLinesDupEnabled and (Length(Stats.TopLinesDup) > 0) then
  begin
    S := S + ', "top_lines": [';
    for i := 0 to EffectiveLimit(Length(Stats.TopLinesDup), True, TopLinesDupLimit) - 1 do
    begin
      if i > 0 then S := S + ',';
      S := S + '{"rank": ' + IntToStr(i + 1) +
        ', "count": ' + IntToStr(Stats.TopLinesDup[i].Count) +
        ', "line": "';
      if Stats.Redact <> [] then
        S := S + JsonEscape(RedactString(Stats.TopLinesDup[i].Line, Stats.Redact))
      else
        S := S + JsonEscape(Stats.TopLinesDup[i].Line);
      S := S + '"}';
    end;
    S := S + ']';
  end;
  // C3-B : clés plates log_levels (--log-level)
  if Stats.LogLevelsEnabled then
  begin
    S := S + ', "log_levels": {"error": ' + IntToStr(Stats.LogLevels[llError]) +
      ', "warn": ' + IntToStr(Stats.LogLevels[llWarn]) +
      ', "info": ' + IntToStr(Stats.LogLevels[llInfo]) +
      ', "debug": ' + IntToStr(Stats.LogLevels[llDebug]) +
      ', "trace": ' + IntToStr(Stats.LogLevels[llTrace]) +
      ', "none": ' + IntToStr(Stats.LogLevels[llNone]) + '}';
  end;
  // C3-C : clé plate tags
  if Stats.TagsEnabled and (Length(Stats.Tags) > 0) then
  begin
    S := S + ', "tags": [';
    for i := 0 to EffectiveLimit(Length(Stats.Tags), True, TopTagsLimit) - 1 do
    begin
      if i > 0 then S := S + ',';
      S := S + '{"rank": ' + IntToStr(i + 1) + ', "tag": "' + JsonEscape(Stats.Tags[i].Tag) +
        '", "count": ' + IntToStr(Stats.Tags[i].Count) + '}';
    end;
    S := S + ']';
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
        // C3-A : lignes pattern (value = pattern, count = matches, length = lines)
        for i := 0 to High(Stats.PatternResults) do
          WriteLn(CsvEscape(Stats.Path), ',pattern,,',
                  CsvEscape(Stats.PatternResults[i].Pattern), ',,',
                  Stats.PatternResults[i].Matches, ',',
                  Stats.PatternResults[i].Lines);
        // C3-A : lignes topline (rank, value = ligne redactée, count)
        if Stats.TopLinesDupEnabled then
        begin
          Limit := EffectiveLimit(Length(Stats.TopLinesDup), ShowAll, TopLinesDupLimit);
          for i := 0 to Limit - 1 do
          begin
            if Stats.Redact <> [] then
              WriteLn(CsvEscape(Stats.Path), ',topline,', i + 1, ',',
                      CsvEscape(RedactString(Stats.TopLinesDup[i].Line, Stats.Redact)), ',,',
                      Stats.TopLinesDup[i].Count, ',')
            else
              WriteLn(CsvEscape(Stats.Path), ',topline,', i + 1, ',',
                      CsvEscape(Stats.TopLinesDup[i].Line), ',,',
                      Stats.TopLinesDup[i].Count, ',');
          end;
        end;
        // C3-B : lignes loglevel (value = nom du niveau, count = lignes)
        if Stats.LogLevelsEnabled then
          for i := Ord(Low(TLogLevel)) to Ord(High(TLogLevel)) do
            WriteLn(CsvEscape(Stats.Path), ',loglevel,,',
                    LogLevelName(TLogLevel(i)), ',,',
                    Stats.LogLevels[TLogLevel(i)], ',');
        // C3-C : lignes tag (rank, value = tag, count)
        if Stats.TagsEnabled then
        begin
          Limit := EffectiveLimit(Length(Stats.Tags), ShowAll, TopTagsLimit);
          for i := 0 to Limit - 1 do
            WriteLn(CsvEscape(Stats.Path), ',tag,', i + 1, ',',
                    CsvEscape(Stats.Tags[i].Tag), ',,',
                    Stats.Tags[i].Count, ',');
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
  WriteLn(Out, '  --sentence-mode=MODE basic | smart (defaut basic ; smart :');
  WriteLn(Out, '                    abreviations et URLs protegees)');
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
  WriteLn(Out, 'Log Sentinel (Cible 3-A/B) :');
  WriteLn(Out, '  --pattern=TEXTE   Compte les occurrences du pattern dans chaque');
  WriteLn(Out, '                    ligne (litteral + | alternance + * ? wildcards,');
  WriteLn(Out, '                    insensible a la casse) ; repetable');
  WriteLn(Out, '  --top-lines=N     Top N des lignes identiques (def. 10, 0 = tous,');
  WriteLn(Out, '                    desactive si l''option est absente)');
  WriteLn(Out, '  --redact=LISTE    email,ipv4,url (virgules) : remplace par *** dans');
  WriteLn(Out, '                    les sorties seulement (compteurs sur le brut)');
  WriteLn(Out, '  --log-level       Compte les lignes par niveau (ERROR>WARN>INFO>');
  WriteLn(Out, '                    DEBUG>TRACE, mot entier insensible a la casse)');
  WriteLn(Out, '  --filter=LISTE    error,warn,info,debug,trace,none (virgules) :');
  WriteLn(Out, '                    filtre l''affichage des lignes (Top Lines,');
  WriteLn(Out, '                    Longest Lines) ; compteurs sur tout le fichier');
  WriteLn(Out, '  --regex-tag=PAT   Extrait et compte les tags (mini-moteur : litteral');
  WriteLn(Out, '                    + [classes] + quantifieurs ? * + ; ex. PLC[0-9]+)');
  WriteLn(Out, '  --top-tags=N      Limite du top des tags (def. 10, 0 = tous)');
  WriteLn(Out, '  --mode=alarm      Raccourci : --log-level + --top-lines + --regex-tag');
  WriteLn(Out, '                    (tag par defaut [A-Z]+[0-9]+ : PLC1, TAG007...)');
  WriteLn(Out, '  --watch           Surveille un fichier (polling) : resume toutes les');
  WriteLn(Out, '                    --interval secondes jusqu''au Ctrl+C ; 1 fichier seul');
  WriteLn(Out, '  --follow          Alias de --watch');
  WriteLn(Out, '  --interval=N      Periode du watch en secondes (def. 2, min 1)');
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
  WriteLn(Out, '  --interactive     Wizard de génération de la ligne de commande (v2.13.0)');
  WriteLn(Out);
  WriteLn(Out, 'Codes de retour : 0 si succes, 1 en cas d''erreur (fichier');
  WriteLn(Out, 'introuvable, glob sans correspondance, option invalide,');
  WriteLn(Out, 'sortie inecrivable, stdin melange avec des fichiers, etc.).');
  WriteLn(Out, 'En mode check : 2 si au moins un check echoue, 3 si warnings');
  WriteLn(Out, 'seulement (le mode analyse garde 0/1).');
end;


end.
