{=============================================================================
  fstats_lex.pas — tokenisation lexicale, n-grams, patterns, redaction,
  niveaux de log, mini-moteur regex-tag (Cibles 2 et 3)
  =============================================================================}
unit fstats_lex;

{$mode objfpc}
{$H+}

interface

uses
  fstats_types, fstats_utf8, SysUtils, Classes;

function IsAsciiWordChar(CP: UInt32): Boolean;
function IsUnicodeWordChar(CP: UInt32): Boolean;
function FoldChar(CP: UInt32; CaseFold: TCaseFold): UInt32;
function MinInt64(A, B: Int64): Int64;
function IsStopWord(const W: string; Mode: TStopWord): Boolean;
function CharClassOf(CP: UInt32): Integer;
function HistClassCount(Kind: THistogramKind): Integer;
function HistogramIndex(Kind: THistogramKind; V: Int64): Integer;
function HistogramRanges(Kind: THistogramKind): TStringArray;
function HistogramName(Kind: THistogramKind): string;
function JoinNGramWords(const Words: TStringArray): string;
procedure QuickSortNGrams(var A: TNGramFreqArray; L, R: Integer);
procedure PruneNGrams(Dict: TNGramDict; Keep: Integer);
procedure AddNGramWindows(Dict: TNGramDict; const Tokens: TStringArray;
                          N: Integer; TopK: Integer);
procedure BuildNGrams(Dict: TNGramDict; TopK: Integer; var OutArr: TNGramFreqArray);
function WildcardMatch(const P, S: string): Boolean;
function PatternMatch(const P, S: string): Boolean;
function WildcardMatchAt(const P, S: string; Start: Integer; out MatchLen: Integer): Boolean;
function CountPatternOccurrences(const P, S: string): Int64;
function IsEmailChar(C: Char): Boolean;
function IsDigit(C: Char): Boolean;
function IsIPv4At(const S: string; Pos: Integer; out Len: Integer): Boolean;
function IsEmailAt(const S: string; Pos: Integer; out Len: Integer): Boolean;
function IsURLAt(const S: string; Pos: Integer; out Len: Integer): Boolean;
function RedactString(const S: string; Modes: TRedactSet): string;
procedure QuickSortTopLines(var A: TTopLineArray; L, R: Integer);
procedure PruneTopLines(Dict: TLineDict; Keep: Integer);
procedure BuildTopLines(Dict: TLineDict; TopK: Integer; var OutArr: TTopLineArray);
function LogLevelName(LL: TLogLevel): string;
function ParseLogLevelName(const S: string; out LL: TLogLevel): Boolean;
function IsAlphaNum(C: Char): Boolean;
function ContainsWord(const S, W: string): Boolean;
function DetectLogLevel(const S: string): TLogLevel;
function ParseTagPattern(const P: string; out Pat: TTagPattern): Boolean;
function MatchTagAt(const Pat: TTagPattern; const S: string; Start: Integer;
                    out MatchLen: Integer): Boolean;
procedure ExtractTags(const Pat: TTagPattern; const S: string; Dict: TTagDict);
procedure QuickSortTags(var A: TTagFreqArray; L, R: Integer);
procedure PruneTags(Dict: TTagDict; Keep: Integer);
procedure BuildTags(Dict: TTagDict; TopK: Integer; var OutArr: TTagFreqArray);

implementation

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
  CIBLE 3-A — MOTEUR LOG SENTINEL : patterns, top-lignes, redaction
  =============================================================================
  --pattern=TEXTE   : matcher interne LITTÉRAL avec alternance '|' et
                      wildcards '*' (n'importe quelle suite) et '?' (un
                      caractère). PAS une regex complète (documenté).
                      Répétable. Matching insensible à la casse (comme le glob
                      Windows) — cohérent avec l'usage log (ERROR/error).
  --top-lines=N     : regroupe les lignes identiques (count + exemple) ;
                      top-K borné comme les n-grams (défaut 10, 0 = tous).
  --redact=LISTE    : email,ipv4,url (séparés par virgule). Remplace par '***'
                      dans les SORTIES (console/JSON/CSV) uniquement ; les
                      compteurs (words, chars, lines…) restent sur le brut.
  =============================================================================}

{-----------------------------------------------------------------------------
  WildcardMatch : Vrai si S correspond au pattern P contenant '*' et '?'.
  v2.15.0 (P2 vague 2) : algorithme greedy iteratif a DEUX reperes
  (derniere etoile + position de reprise). L'ancienne version recursive
  permettait un backtracking exponentiel (*a*a*a*b sur "aaaa...b" gelait).
  Semantique inchangee : '*' = n'importe quelle sequence (y compris vide),
  '?' = un caractere, litteraux insensibles a la casse (UpCase ASCII).
  Complexite : O(len(P) x len(S)) au pire, aucune recursion (pile bornee).
  -----------------------------------------------------------------------------}
function WildcardMatch(const P, S: string): Boolean;
var
  pi, si, starPi, starSi: Integer;
  m, n: Integer;
begin
  m := Length(P);
  n := Length(S);
  pi := 1;
  si := 1;
  starPi := 0;      // position (pattern) de la derniere etoile vue ; 0 = aucune
  starSi := 0;      // position (texte) OU cette etoile a recommence a consommer
  while si <= n do
  begin
    if pi <= m then
    begin
      if P[pi] = '*' then
      begin
        starPi := pi;
        starSi := si;
        Inc(pi);              // l'etoile essaie de consommer 0 caractere d'abord
      end
      else if (P[pi] = '?') or (UpCase(P[pi]) = UpCase(S[si])) then
      begin
        Inc(pi);
        Inc(si);
      end
      else if starPi > 0 then
      begin
        Inc(starSi);           // la derniere etoile consomme un caractere de plus
        si := starSi;
        pi := starPi + 1;
      end
      else
        Exit(False);           // mismatch sans etoile de repli : echec
    end
    else if starPi > 0 then
    begin
      // Pattern epuise mais texte restant : l'etoile doit absorber la suite
      Inc(starSi);
      si := starSi;
      pi := starPi + 1;
      if si > n then Break;    // absorbe tout : verifier la queue du pattern
    end
    else
      Exit(False);             // pattern epuise, texte restant, pas d'etoile : echec
  end;
  // Texte epuise : le reste du pattern doit etre des etoiles (consomment vide)
  while (pi <= m) and (P[pi] = '*') do
    Inc(pi);
  Result := pi > m;
end;

{-----------------------------------------------------------------------------
  PatternMatch : Vrai si la ligne S correspond au pattern complet P.
  P peut contenir '|' pour l'alternance (ex. 'ERROR|WARN'). Chaque segment
  entre '|' est matché avec WildcardMatch.
  -----------------------------------------------------------------------------}
function PatternMatch(const P, S: string): Boolean;
var
  Seg, Rest: string;
  i: Integer;
begin
  Result := False;
  Rest := P;
  while Rest <> '' do
  begin
    i := Pos('|', Rest);
    if i > 0 then
    begin
      Seg := Copy(Rest, 1, i - 1);
      Rest := Copy(Rest, i + 1, Length(Rest));
    end
    else
    begin
      Seg := Rest;
      Rest := '';
    end;
    if WildcardMatch(Seg, S) then Exit(True);
  end;
end;

{-----------------------------------------------------------------------------
  WildcardMatchAt : Vrai si le pattern P matche un PRÉFIXE de S à partir de
  la position Start (recherche de sous-chaîne, pas match de la ligne entière).
  Retourne dans MatchLen la longueur du match (caractères de S consommés).
  -----------------------------------------------------------------------------}
function WildcardMatchAt(const P, S: string; Start: Integer; out MatchLen: Integer): Boolean;
var
  pi, si, starPi, starSi: Integer;
  m, n: Integer;
label
  Mismatch;
begin
  m := Length(P);
  n := Length(S);
  pi := 1;
  si := Start;
  starPi := 0;
  starSi := Start;
  while True do
  begin
    // Avancer tant que pattern et texte s'accordent
    while pi <= m do
    begin
      if P[pi] = '*' then
      begin
        starPi := pi;
        starSi := si;
        Inc(pi);              // l'etoile essaie 0 caractere d'abord (min-d'abord)
      end
      else if (si <= n) and ((P[pi] = '?') or (UpCase(P[pi]) = UpCase(S[si]))) then
      begin
        Inc(pi);
        Inc(si);
      end
      else
        goto Mismatch;
    end;
    // Pattern epuise = match d'un prefixe de S (semantique At, v2.13.1)
    MatchLen := si - Start;
    Exit(True);
Mismatch:
    // Retenter depuis la derniere etoile, un caractere de plus
    if (starPi = 0) or (starSi > n) then
      Break;                 // plus d'etoile ou etoile saturee : echec
    Inc(starSi);
    si := starSi;
    pi := starPi + 1;
  end;
  Result := False;
  MatchLen := 0;
end;

{-----------------------------------------------------------------------------
  CountPatternOccurrences : Compte le nombre d'occurrences du pattern P dans
  la ligne S. Occurrences non chevauchantes, recherche de gauche à droite
  (sémantique documentée).
  -----------------------------------------------------------------------------}
function CountPatternOccurrences(const P, S: string): Int64;
var
  Seg, Rest: string;
  i, StartPos, SegLen: Integer;
  Found: Boolean;
begin
  Result := 0;
  Rest := P;
  // Pour chaque segment d'alternance, compter les occurrences dans S
  while Rest <> '' do
  begin
    i := Pos('|', Rest);
    if i > 0 then
    begin
      Seg := Copy(Rest, 1, i - 1);
      Rest := Copy(Rest, i + 1, Length(Rest));
    end
    else
    begin
      Seg := Rest;
      Rest := '';
    end;
    // Compter les occurrences non chevauchantes de Seg dans S
    StartPos := 1;
    while StartPos <= Length(S) do
    begin
      Found := False;
      for i := StartPos to Length(S) do
      begin
        if WildcardMatchAt(Seg, S, i, SegLen) then
        begin
          if SegLen > 0 then
          begin
            Inc(Result);
            StartPos := i + SegLen;
            if StartPos > Length(S) + 1 then StartPos := Length(S) + 1;
            Found := True;
          end
          else
            // v2.15.0 (P2 vague 2) : match de longueur NULLE (pattern
            // reduit a des jokers, ex. '*', '**' ou segment vide d'une
            // alternation 'a||b') — l'ancien code rebouclait ici a
            // l'infini (StartPos := i + 0 = i). Un match vide n'est pas
            // une occurrence : on avance d'une position, sans compter.
            StartPos := i + 1;
          Break;
        end;
      end;
      if not Found then Break;
    end;
  end;
end;

{-----------------------------------------------------------------------------
  IsEmailChar : Vrai si C peut faire partie d'une adresse email locale
  (lettres, chiffres, . _ + -). Le '@' et le domaine sont traités à part.
  -----------------------------------------------------------------------------}
function IsEmailChar(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or
            ((C >= 'A') and (C <= 'Z')) or
            ((C >= '0') and (C <= '9')) or
            (C = '.') or (C = '_') or (C = '+') or (C = '-');
end;

{-----------------------------------------------------------------------------
  IsDigit : Vrai si C est un chiffre ASCII.
  -----------------------------------------------------------------------------}
function IsDigit(C: Char): Boolean;
begin
  Result := (C >= '0') and (C <= '9');
end;

{-----------------------------------------------------------------------------
  IsIPv4At : Vrai si S contient une adresse IPv4 commençant à la position Pos.
  Format : 4 groupes de 1-3 chiffres séparés par '.'. Retourne la longueur
  totale (9 à 15 caractères).
  -----------------------------------------------------------------------------}
function IsIPv4At(const S: string; Pos: Integer; out Len: Integer): Boolean;
var
  i, Group, DigitCount: Integer;
begin
  Result := False;
  Len := 0;
  i := Pos;
  for Group := 1 to 4 do
  begin
    DigitCount := 0;
    while (i <= Length(S)) and IsDigit(S[i]) and (DigitCount < 3) do
    begin
      Inc(i);
      Inc(DigitCount);
    end;
    if DigitCount = 0 then Exit;
    Inc(Len, DigitCount);
    if Group < 4 then
    begin
      if (i > Length(S)) or (S[i] <> '.') then Exit;
      Inc(i);
      Inc(Len);
    end;
  end;
  // Le caractère suivant ne doit pas être un chiffre ni un point (sinon c'est
  // un nombre décimal ou une version, pas une IPv4)
  if (i <= Length(S)) and (IsDigit(S[i]) or (S[i] = '.')) then Exit;
  Result := True;
end;

{-----------------------------------------------------------------------------
  IsEmailAt : Vrai si S contient un email commençant à la position Pos.
  Format : partie-locale '@' domaine avec au moins un point dans le domaine.
  -----------------------------------------------------------------------------}
function IsEmailAt(const S: string; Pos: Integer; out Len: Integer): Boolean;
var
  i, AtPos, DotPos: Integer;
begin
  Result := False;
  Len := 0;
  // Trouver le '@' après une suite de caractères email
  i := Pos;
  while (i <= Length(S)) and IsEmailChar(S[i]) do Inc(i);
  if (i <= Length(S)) and (S[i] = '@') and (i > Pos) then
  begin
    AtPos := i;
    Inc(i);
    // Domaine : au moins un caractère, puis un point, puis au moins un caractère
    if (i <= Length(S)) and IsEmailChar(S[i]) then
    begin
      DotPos := 0;
      while (i <= Length(S)) and (IsEmailChar(S[i]) or (S[i] = '-')) do
      begin
        if S[i] = '.' then DotPos := i;
        Inc(i);
      end;
      if (DotPos > AtPos + 1) and (DotPos < i - 1) then
      begin
        Len := i - Pos;
        Result := True;
      end;
    end;
  end;
end;

{-----------------------------------------------------------------------------
  IsURLAt : Vrai si S contient une URL commençant à la position Pos
  (http:// ou https://). S'étend jusqu'au prochain blanc ou fin de chaîne.
  -----------------------------------------------------------------------------}
function IsURLAt(const S: string; Pos: Integer; out Len: Integer): Boolean;
var
  i: Integer;
  Prefix: string;
begin
  Result := False;
  Len := 0;
  if (Pos + 6 <= Length(S) + 1) and
     ((Copy(S, Pos, 7) = 'http://') or (Copy(S, Pos, 8) = 'https://')) then
  begin
    if Copy(S, Pos, 7) = 'http://' then Prefix := 'http://' else Prefix := 'https://';
    i := Pos + Length(Prefix);
    while (i <= Length(S)) and (S[i] > ' ') do Inc(i);
    Len := i - Pos;
    if Len > Length(Prefix) then Result := True;
  end;
end;

{-----------------------------------------------------------------------------
  RedactString : Applique la redaction (email, ipv4, url) à la chaîne S.
  Remplace chaque occurrence par '***'. Les compteurs ne sont PAS affectés
  (cette fonction n'est appelée que dans les exports/affichage).
  -----------------------------------------------------------------------------}
function RedactString(const S: string; Modes: TRedactSet): string;
var
  i, L, Skip: Integer;
begin
  Result := '';
  i := 1;
  L := Length(S);
  while i <= L do
  begin
    Skip := 0;
    if (rmEmail in Modes) and IsEmailAt(S, i, Skip) then
    begin
      Result := Result + '***';
      Inc(i, Skip);
      Continue;
    end;
    if (rmIPv4 in Modes) and IsIPv4At(S, i, Skip) then
    begin
      Result := Result + '***';
      Inc(i, Skip);
      Continue;
    end;
    if (rmURL in Modes) and IsURLAt(S, i, Skip) then
    begin
      Result := Result + '***';
      Inc(i, Skip);
      Continue;
    end;
    Result := Result + S[i];
    Inc(i);
  end;
end;

{-----------------------------------------------------------------------------
  QuickSortTopLines : Tri décroissant par Count, puis croissant par Line
  (déterminisme des égalités).
  -----------------------------------------------------------------------------}
procedure QuickSortTopLines(var A: TTopLineArray; L, R: Integer);
var
  I, J: Integer;
  P, T: TTopLine;
begin
  if L >= R then Exit;
  I := L; J := R;
  P := A[(L + R) div 2];
  repeat
    while (A[I].Count > P.Count) or
          ((A[I].Count = P.Count) and (CompareStr(A[I].Line, P.Line) < 0)) do Inc(I);
    while (A[J].Count < P.Count) or
          ((A[J].Count = P.Count) and (CompareStr(A[J].Line, P.Line) > 0)) do Dec(J);
    if I <= J then
    begin
      T := A[I]; A[I] := A[J]; A[J] := T;
      Inc(I); Dec(J);
    end;
  until I > J;
  if L < J then QuickSortTopLines(A, L, J);
  if I < R then QuickSortTopLines(A, I, R);
end;

{-----------------------------------------------------------------------------
  PruneTopLines : Réduit le dictionnaire des lignes identiques à ses Keep
  entrées les plus fréquentes (mémoire bornée, comme PruneNGrams).
  -----------------------------------------------------------------------------}
procedure PruneTopLines(Dict: TLineDict; Keep: Integer);
var
  Arr: TTopLineArray;
  Pair: TWordPair;
  i: Integer;
begin
  if Keep <= 0 then Exit;
  SetLength(Arr, Dict.Count);
  i := 0;
  for Pair in Dict do
  begin
    Arr[i].Line := Pair.Key;
    Arr[i].Count := Pair.Value;
    Inc(i);
  end;
  QuickSortTopLines(Arr, 0, High(Arr));
  if Length(Arr) > Keep then SetLength(Arr, Keep);
  Dict.Clear;
  for i := 0 to High(Arr) do
    Dict.Add(Arr[i].Line, Arr[i].Count);
end;

{-----------------------------------------------------------------------------
  BuildTopLines : Convertit le dictionnaire en tableau top-K trié.
  -----------------------------------------------------------------------------}
procedure BuildTopLines(Dict: TLineDict; TopK: Integer; var OutArr: TTopLineArray);
var
  Arr: TTopLineArray;
  i, Limit: Integer;
  Pair: TWordPair;
begin
  SetLength(Arr, Dict.Count);
  i := 0;
  for Pair in Dict do
  begin
    Arr[i].Line := Pair.Key;
    Arr[i].Count := Pair.Value;
    Inc(i);
  end;
  QuickSortTopLines(Arr, 0, High(Arr));
  Limit := Length(Arr);
  if (TopK > 0) and (Limit > TopK) then Limit := TopK;
  SetLength(OutArr, Limit);
  for i := 0 to Limit - 1 do
  begin
    OutArr[i].Line := Arr[i].Line;
    OutArr[i].Count := Arr[i].Count;
  end;
end;

{-----------------------------------------------------------------------------
  LogLevelName : Nom canonique minuscule d'un niveau ('error', 'warn', ...).
  -----------------------------------------------------------------------------}
function LogLevelName(LL: TLogLevel): string;
begin
  case LL of
    llError:  Result := 'error';
    llWarn:   Result := 'warn';
    llInfo:   Result := 'info';
    llDebug:  Result := 'debug';
    llTrace:  Result := 'trace';
    else      Result := 'none';
  end;
end;

{-----------------------------------------------------------------------------
  ParseLogLevelName : Parse un nom de niveau ('error','warn','info','debug',
  'trace','none', insensible à la casse). Retourne False si inconnu.
  -----------------------------------------------------------------------------}
function ParseLogLevelName(const S: string; out LL: TLogLevel): Boolean;
var
  V: string;
begin
  V := LowerCase(Trim(S));
  if V = 'error' then LL := llError
  else if V = 'warn' then LL := llWarn
  else if V = 'info' then LL := llInfo
  else if V = 'debug' then LL := llDebug
  else if V = 'trace' then LL := llTrace
  else if V = 'none' then LL := llNone
  else Exit(False);
  Result := True;
end;

{-----------------------------------------------------------------------------
  IsAlphaNum : Vrai si C est une lettre ou un chiffre ASCII (borne de mot).
  -----------------------------------------------------------------------------}
function IsAlphaNum(C: Char): Boolean;
begin
  Result := ((C >= 'a') and (C <= 'z')) or
            ((C >= 'A') and (C <= 'Z')) or
            ((C >= '0') and (C <= '9'));
end;

{-----------------------------------------------------------------------------
  ContainsWord : Vrai si le mot W (ex. 'ERROR') apparaît dans S comme MOT
  ENTIER (délimité par des non-alphanumériques ou les bords de chaîne),
  insensible à la casse.
  -----------------------------------------------------------------------------}
function ContainsWord(const S, W: string): Boolean;
var
  i, WL: Integer;
begin
  Result := False;
  WL := Length(W);
  if WL = 0 then Exit;
  for i := 1 to Length(S) - WL + 1 do
  begin
    if UpCase(Copy(S, i, WL)) = UpCase(W) then
    begin
      if ((i = 1) or (not IsAlphaNum(S[i - 1]))) and
         ((i + WL > Length(S)) or (not IsAlphaNum(S[i + WL]))) then
        Exit(True);
    end;
  end;
end;

{-----------------------------------------------------------------------------
  DetectLogLevel : Détecte le niveau de log d'une ligne. Cherche les mots
  entiers ERROR, WARN, INFO, DEBUG, TRACE (insensible à la casse) dans cet
  ordre de priorité ; le premier trouvé gagne. Aucun → llNone.
  -----------------------------------------------------------------------------}
function DetectLogLevel(const S: string): TLogLevel;
begin
  if ContainsWord(S, 'ERROR') then Exit(llError);
  // v2.14.1 (P2) : WARNING = mot entier à part entière (log4j, Python,
  // Node — le niveau warn le plus répandu du monde réel). WARN reste
  // reconnu tel quel ; les autres niveaux inchangés (mot entier).
  if ContainsWord(S, 'WARNING') then Exit(llWarn);
  if ContainsWord(S, 'WARN') then Exit(llWarn);
  if ContainsWord(S, 'INFO') then Exit(llInfo);
  if ContainsWord(S, 'DEBUG') then Exit(llDebug);
  if ContainsWord(S, 'TRACE') then Exit(llTrace);
  Result := llNone;
end;

{=============================================================================
  CIBLE 3-C — MINI-MOTEUR REGEX-TAG (subset documenté, PAS une regex complète)
  =============================================================================
  Syntaxe supportée :
    - littéral        : 'P', 'L', 'C' ...
    - classe [...]    : [0-9], [a-z], [A-Z], [a-zA-Z0-9_], chars isolés [abc]
    - quantifieurs    : '?' (0..1), '+' (1..inf), '*' (0..inf) après un token ;
                        défaut = exactement 1.
  Exemples : 'PLC[0-9]+' -> PLC1, PLC23 ; '[A-Z]+[0-9]+' -> TAG007, MOTOR3.
  Extraction : occurrences non chevauchantes, de gauche à droite, dans chaque
  ligne. Le tag extrait est la sous-chaîne matchée.
  =============================================================================}

{-----------------------------------------------------------------------------
  ParseTagPattern : Parse le pattern P en séquence de tokens. Retourne False
  si syntaxe invalide (classe non fermée, quantifieur sans token, etc.).
  -----------------------------------------------------------------------------}
function ParseTagPattern(const P: string; out Pat: TTagPattern): Boolean;
var
  i, n: Integer;
  Tok: TTagToken;
  procedure AddTok;
  begin
    SetLength(Pat, Length(Pat) + 1);
    Pat[High(Pat)] := Tok;
  end;
begin
  Result := False;
  SetLength(Pat, 0);
  i := 1;
  n := Length(P);
  while i <= n do
  begin
    Tok.MinRep := 1;
    Tok.MaxRep := 1;
    if P[i] = '[' then
    begin
      // Classe [..] : parser jusqu'à ']'
      Inc(i);
      Tok.IsClass := True;
      Tok.ClassSet := [];
      if (i <= n) and (P[i] = ']') then
      begin
        // [] vide = classe contenant ']' littéral (convention) — simplifié : interdit
        Exit;
      end;
      while (i <= n) and (P[i] <> ']') do
      begin
        if (i + 2 <= n) and (P[i + 1] = '-') and (P[i + 2] <> ']') then
        begin
          // Plage c1-c2
          Tok.ClassSet := Tok.ClassSet + [P[i]..P[i + 2]];
          Inc(i, 3);
        end
        else
        begin
          Tok.ClassSet := Tok.ClassSet + [P[i]];
          Inc(i);
        end;
      end;
      if (i > n) or (P[i] <> ']') then Exit;  // classe non fermée
      Inc(i);  // consommer ']'
    end
    else
    begin
      Tok.IsClass := False;
      Tok.Ch := P[i];
      Inc(i);
    end;
    // Quantifieur optionnel
    if (i <= n) then
    begin
      case P[i] of
        '?': begin Tok.MinRep := 0; Tok.MaxRep := 1; Inc(i); end;
        '+': begin Tok.MinRep := 1; Tok.MaxRep := MaxInt; Inc(i); end;
        '*': begin Tok.MinRep := 0; Tok.MaxRep := MaxInt; Inc(i); end;
      end;
    end;
    AddTok;
  end;
  Result := Length(Pat) > 0;
end;

{-----------------------------------------------------------------------------
  MatchTagAt : Tente de matcher tout le pattern Pat a partir de la position
  Start dans S. Retourne la longueur totale matchée dans MatchLen.
  v2.15.0 (P2 vague 2) : simulation NFA en ensemble d'etats lineaire —
  O(len(S) x len(Pat)) par position de depart, ZERO backtracking. L'ancienne
  version recursive (gloutonne avec backtracking) pouvait GELER sur des
  patterns a quantifieurs imbriques (a*a*a*a*b sur "aaaa...b" : exploration
  exponentielle ; amplifie par --mode=alarm et son pattern par defaut).
  Semantique : MatchLen = LONGUEUR DU MATCH LE PLUS LONG depuis Start
  (accepte s'ecrit : tous les tokens consommes ; un match vide = True/0,
  l'appelant ExtractTags ignore deja les matchs vides, ML > 0).
  Etats : Pre[0..k] = "tokens 0..i-1 completement consommes" ;
  Loop[i] = "au moins une repetition du token i en cours" (peut continuer).
  -----------------------------------------------------------------------------}
function MatchTagAt(const Pat: TTagPattern; const S: string; Start: Integer;
                    out MatchLen: Integer): Boolean;

  function TokMatches(const Tok: TTagToken; c: Char): Boolean;
  begin
    if Tok.IsClass then
      Result := c in Tok.ClassSet
    else
      Result := UpCase(c) = UpCase(Tok.Ch);
  end;

var
  k, n, i, q: Integer;
  Pre, NextPre, TmpPre: array of Boolean;
  Loop, NextLoop, TmpLoop: array of Boolean;
  AnyActive: Boolean;
  BestLen: Integer;
begin
  k := Length(Pat);
  n := Length(S);
  MatchLen := 0;
  if k = 0 then
    Exit(False);

  SetLength(Pre, k + 1);
  SetLength(NextPre, k + 1);
  SetLength(Loop, k);
  SetLength(NextLoop, k);
  for i := 0 to k do Pre[i] := False;
  for i := 0 to k - 1 do Loop[i] := False;
  Pre[0] := True;

  // Fermeture epsilon initiale (saut des tokens facultatifs, chaine montante)
  for i := 0 to k - 1 do
    if Pre[i] and (Pat[i].MinRep = 0) then
      Pre[i + 1] := True;

  // Match vide possible (pattern entier sautable) — l'appelant filtre ML > 0
  if Pre[k] then
    BestLen := 0
  else
    BestLen := -1;

  q := Start;
  while q <= n do
  begin
    // Passage caracteres : chaque etat actif consomme S[q] selon son token
    for i := 0 to k do NextPre[i] := False;
    for i := 0 to k - 1 do NextLoop[i] := False;
    for i := 0 to k - 1 do
    begin
      if not TokMatches(Pat[i], S[q]) then Continue;
      if Pre[i] then
        NextLoop[i] := True;                       // 1re repetition du token i
      if Loop[i] and (Pat[i].MaxRep > 1) then
        NextLoop[i] := True;                       // repetition suivante
    end;
    // Fermeture epsilon apres consommation (passage unique montant suffit :
    // Pre[i] ne se propage que vers Pre[i+1], Loop[i] aussi)
    for i := 0 to k - 1 do
    begin
      if NextPre[i] and (Pat[i].MinRep = 0) then
        NextPre[i + 1] := True;
      if NextLoop[i] then
        NextPre[i + 1] := True;
    end;
    // Echange des ensembles d'etats
    TmpPre := Pre; Pre := NextPre; NextPre := TmpPre;
    TmpLoop := Loop; Loop := NextLoop; NextLoop := TmpLoop;

    // Etats actifs ?
    AnyActive := Pre[k];
    for i := 0 to k - 1 do
      AnyActive := AnyActive or Loop[i] or Pre[i];
    if not AnyActive then
      Break;

    Inc(q);
    if Pre[k] then
      BestLen := q - Start;   // consomme Start..q-1 : match le plus long a jour
  end;

  if BestLen >= 0 then
  begin
    Result := True;
    MatchLen := BestLen;
  end
  else
  begin
    Result := False;
    MatchLen := 0;
  end;
end;

{-----------------------------------------------------------------------------
  ExtractTags : Extrait toutes les occurrences non chevauchantes du pattern
  dans la ligne S et les ajoute au dictionnaire Dict (tag -> count).
  -----------------------------------------------------------------------------}
procedure ExtractTags(const Pat: TTagPattern; const S: string; Dict: TTagDict);
var
  i, ML: Integer;
  Tag: string;
  C: Int64;
begin
  i := 1;
  while i <= Length(S) do
  begin
    if MatchTagAt(Pat, S, i, ML) and (ML > 0) then
    begin
      Tag := Copy(S, i, ML);
      if Dict.TryGetValue(Tag, C) then
        Dict[Tag] := C + 1
      else
        Dict.Add(Tag, 1);
      Inc(i, ML);
    end
    else
      Inc(i);
  end;
end;

{-----------------------------------------------------------------------------
  QuickSortTags / PruneTags / BuildTags : tri, borne mémoire et conversion
  (mêmes sémantiques que QuickSortTopLines / PruneTopLines / BuildTopLines).
  -----------------------------------------------------------------------------}
procedure QuickSortTags(var A: TTagFreqArray; L, R: Integer);
var
  I, J: Integer;
  P, T: TTagFreq;
begin
  if L >= R then Exit;
  I := L; J := R;
  P := A[(L + R) div 2];
  repeat
    while (A[I].Count > P.Count) or
          ((A[I].Count = P.Count) and (CompareStr(A[I].Tag, P.Tag) < 0)) do Inc(I);
    while (A[J].Count < P.Count) or
          ((A[J].Count = P.Count) and (CompareStr(A[J].Tag, P.Tag) > 0)) do Dec(J);
    if I <= J then
    begin
      T := A[I]; A[I] := A[J]; A[J] := T;
      Inc(I); Dec(J);
    end;
  until I > J;
  if L < J then QuickSortTags(A, L, J);
  if I < R then QuickSortTags(A, I, R);
end;

procedure PruneTags(Dict: TTagDict; Keep: Integer);
var
  Arr: TTagFreqArray;
  Pair: TWordPair;
  i: Integer;
begin
  if Keep <= 0 then Exit;
  SetLength(Arr, Dict.Count);
  i := 0;
  for Pair in Dict do
  begin
    Arr[i].Tag := Pair.Key;
    Arr[i].Count := Pair.Value;
    Inc(i);
  end;
  QuickSortTags(Arr, 0, High(Arr));
  if Length(Arr) > Keep then SetLength(Arr, Keep);
  Dict.Clear;
  for i := 0 to High(Arr) do
    Dict.Add(Arr[i].Tag, Arr[i].Count);
end;

procedure BuildTags(Dict: TTagDict; TopK: Integer; var OutArr: TTagFreqArray);
var
  Arr: TTagFreqArray;
  i, Limit: Integer;
  Pair: TWordPair;
begin
  SetLength(Arr, Dict.Count);
  i := 0;
  for Pair in Dict do
  begin
    Arr[i].Tag := Pair.Key;
    Arr[i].Count := Pair.Value;
    Inc(i);
  end;
  QuickSortTags(Arr, 0, High(Arr));
  Limit := Length(Arr);
  if (TopK > 0) and (Limit > TopK) then Limit := TopK;
  SetLength(OutArr, Limit);
  for i := 0 to Limit - 1 do
  begin
    OutArr[i].Tag := Arr[i].Tag;
    OutArr[i].Count := Arr[i].Count;
  end;
end;


end.
