{=============================================================================
  fstats_checks.pas — moteur de checks, baseline NDJSON, --compare/--fail-on-delta (Cible 1 B+C)
  =============================================================================}
unit fstats_checks;

{$mode objfpc}
{$H+}

interface

uses
  fstats_types, fstats_utf8, fstats_glob, fstats_lex,
  SysUtils, Classes, Generics.Collections, Generics.Defaults;

function OpToStr(Op: TCheckOp): string;
function CheckStatusStr(St: TCheckStatus; Upper: Boolean): string;
function IsValidMetricName(const M: string): Boolean;
function ContainsCheckOp(const S: string): Boolean;
function IsOpToken(const S: string): Boolean;
function ParseNumber(const S: string; out V: Double): Boolean;
function CanonMetricFailIf(const M: string): string;
function CanonMetricDelta(const M: string): string;
function CheckMetricValue(const Stats: TStats; const Metric: string;
                          out V: Double): Boolean;
function EvalCompare(Actual: Double; Op: TCheckOp; Threshold: Double): Boolean;
function FormatFloatTrimSigned(V: Double; Decimals: Integer): string;
function ParseCheckSpec(const Arg: string; out Metric: string; out Op: TCheckOp;
                        out Threshold: Double): Integer;
function ParseDeltaSpec(const Arg: string; out Metric: string;
                        out Threshold: Double): Integer;
procedure AppendUTF8(var R: string; CP: UInt32);
function JSONUnescape(const S: string): string;
procedure ParseJSONObject(const S: string; var Keys, Values: TStringArray);
function SplitJSONObjects(const S: string; var Objs: TStringArray): Boolean;
function BaselineValue(const E: TBaselineEntry; const Key: string;
                       out V: Double): Boolean;
function BaselineStr(const E: TBaselineEntry; const Key: string): string;
procedure LoadBaseline(const Path: string; var Baseline: TBaselineArray);
procedure EvaluateChecks(const Stats: TStats; const Checks: TCheckArray;
                         const Baseline: TBaselineArray; const ActualSha: string;
                         out Results: TCheckResultArray);

implementation

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
  BaselineStr : Valeur CHAÎNE d'une clé d'entrée baseline (v2.16.0, intégrité :
  la clé "sha256" produite par --summary-json). Vide si absente.
  -----------------------------------------------------------------------------}
function BaselineStr(const E: TBaselineEntry; const Key: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(E.Keys) do
    if E.Keys[i] = Key then
    begin
      Result := E.Values[i];
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
                         const Baseline: TBaselineArray; const ActualSha: string;
                         out Results: TCheckResultArray);
var
  i, j, Entry, Ordinal: Integer;
  V, Base, Delta: Double;
  Key: string;
  ShaBase: string;
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

  // v2.16.0 (P2 vague 3) : intégrité de la baseline. Si l'entrée baseline
  // porte une clé "sha256" (produite par --summary-json) et que le contenu
  // actuel du fichier hash diffère, le check "sha256" échoue : le fichier a
  // changé de contenu — ses métriques stables peuvent masquer la dérive
  // (token collé, ligne réécrite). Un hash identique n'émet rien (pas de
  // bruit) ; une baseline ancienne sans clé saute la vérification
  // (rétrocompatible). Non applicable à stdin ni aux fichiers illisibles
  // (ActualSha = '').
  if (Entry >= 0) and (ActualSha <> '') then
  begin
    ShaBase := BaselineStr(Baseline[Entry], 'sha256');
    if (ShaBase <> '') and (ShaBase <> ActualSha) then
    begin
      R.Actual := 1;                 // 1 = divergence (documenté SEMANTIQUE)
      R.Metric := 'sha256';
      R.Op := opNe;
      R.Threshold := 0;
      R.IsDelta := False;
      R.DeltaInf := False;
      R.Status := csFail;
      R.Id := 'sha256';
      SetLength(Results, Length(Results) + 1);
      Results[High(Results)] := R;
    end
    else if (ShaBase <> '') and (ShaBase = ActualSha) then
    begin
      // Hash vérifié identique : signal positif, émis comme check ok (v2.16.0
      // — l'intégrité PROUVÉE est une information, pas du bruit).
      R.Actual := 0;
      R.Metric := 'sha256';
      R.Op := opNe;
      R.Threshold := 0;
      R.IsDelta := False;
      R.DeltaInf := False;
      R.Status := csOk;
      R.Id := 'sha256';
      SetLength(Results, Length(Results) + 1);
      Results[High(Results)] := R;
    end;
  end;
end;


end.
