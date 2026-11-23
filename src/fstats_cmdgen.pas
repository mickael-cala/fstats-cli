{=============================================================================
  fstats_cmdgen.pas — générateur de ligne de commande pour fstats (v2.13.0)
  =============================================================================
  Logique partagée entre :
    - fstats --interactive   (wizard intégré)
    - fcmd                   (binaire compagnon standalone)

  Le wizard pose des questions (profil + options par catégorie), construit la
  ligne de commande, l'affiche, et peut l'exécuter après confirmation.
  Lecture ligne par ligne sur stdin : pilotable en pipe (tests CI).
  =============================================================================}
{$codepage utf8}  // Source UTF-8 : littéraux chaîne étiquetés UTF-8
unit fstats_cmdgen;

{$mode objfpc}
{$H+}

interface

uses
  SysUtils, Classes
  {$IFDEF MSWINDOWS}, Windows{$ENDIF}
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

const
  CMDGEN_VERSION = '2.14.0';
  OPT_COUNT = 49;   // dont 1 entrée spéciale '' = fichiers positionnels

type
  TOptKind = (okFlag, okValue);
  TCmdOpt = record
    Name: string;      // ex. '--json'  ('' pour les fichiers positionnels)
    Cat: Integer;      // 1..7
    Kind: TOptKind;
    Prompt: string;
  end;

{ Construit la ligne de commande à partir des tokens (quotés si besoin).
  CmdName = nom du programme (ex. 'fstats'). }
function BuildCmd(const CmdName: string; const Tokens: TStringList): string;

{ Quote un argument pour le shell courant (cmd.exe / sh). v2.14.0 (P1-1) :
  quotte aussi dès qu'un MÉTACARACTÈRE est présent — l'ancienne règle
  « espace/tab/guillemet » laissait passer `; & | $ ( ) < >` qui s'exécutent
  au collage dans un shell. Limite documentée : cmd.exe développe %VAR%
  même entre guillemets (cf. doc/AUDIT-SECURITE.md). }
function CmdQuote(const S: string): string;

{ v2.14.0 (P1-1, audit sécurité) : exécute un programme avec ses arguments
  SÉPARÉS via SysUtils.ExecuteProcess — jamais de ligne de commande assemblée,
  jamais de shell (l'ancien chemin Unix passait par FpSystem = sh -c, où un
  `;` ou `$(…)` dans une valeur exécutait du code arbitraire). Rend le exit
  code du processus, -1 si le lancement échoue. }
function RunArgs(const ExePath: string; const Args: array of string): Integer;

{ Même chose depuis les tokens du wizard (construit l'argv). }
function RunTokens(const ExePath: string; const Tokens: TStringList): Integer;

{ Retrouve l'index du token d'une option (Name='' → premier token positionnel). }
function FindOpt(const Tokens: TStringList; const Name: string): Integer;

{ Valeur courante d'une option ('' si absente). Pour okFlag: '1' si présent. }
function OptValue(const Tokens: TStringList; const Name: string): string;

{ Pose la valeur d'une option (flag: '1' = on, '' = off ; value: '' = retire). }
procedure SetOpt(const Tokens: TStringList; const Opt: TCmdOpt; const V: string);

{ Applique un profil (1=corpus, 2=log, 3=gate) : pré-remplit des tokens. }
procedure ApplyProfil(Profil: Integer; const Tokens: TStringList);

{ Le wizard interactif : remplit Tokens, rend False si annulé (EOF). }
function RunWizard(const CmdName: string; const Tokens: TStringList;
                   PresetProfil: Integer): Boolean;

{ Affiche la commande générée. }
procedure PrintCmd(const CmdName: string; const Tokens: TStringList);

{ Table des options (remplie à l'initialization). }
function OptAt(Index: Integer): TCmdOpt;
function CatName(Cat: Integer): string;

implementation

var
  OPTS: array[1..OPT_COUNT] of TCmdOpt;
  CAT_NAMES: array[1..7] of string;

// Définitions : 'Name|Cat|Kind|Prompt'  Kind: F=flag, V=valeur  (Name vide = fichiers)
const
  OPT_DEFS: array[1..OPT_COUNT] of string = (
    '|1|V|Fichiers / globs (séparés par des espaces) :',
    '--stdin|1|F|Lire stdin (-) ?',
    '--recursive|1|V|--recursive=DIR :',
    '--include|1|V|--include=GLOB :',
    '--exclude|1|V|--exclude=GLOB :',
    '--max-depth|1|V|--max-depth=N :',
    '--word-mode|2|V|--word-mode=raw|ascii|unicode :',
    '--casefold|2|V|--casefold=ascii|unicode|none :',
    '--sentence-mode|2|V|--sentence-mode=basic|smart :',
    '--stopwords|2|V|--stopwords=fr|en|none :',
    '--max-unique|2|V|--max-unique=N :',
    '--top-words|2|V|--top-words=N :',
    '--top-chars|2|V|--top-chars=N :',
    '--top-lines|2|V|--top-lines=N :',
    '--ngrams|2|V|--ngrams=N (entier 1-5) :',
    '--top-ngrams|2|V|--top-ngrams=K :',
    '--char-classes|2|F|--char-classes ?',
    '--histogram|2|V|--histogram=line_length|word_length|words_per_sentence :',
    '--lexical-stats|2|F|--lexical-stats ?',
    '--readability|2|F|--readability ?',
    '--all|3|F|--all (tout exporter, pas de limite Top 10) ?',
    '--char|3|F|--char (caractères seuls) ?',
    '--word|3|F|--word (mots seuls) ?',
    '--line|3|F|--line (lignes seules) ?',
    '--no-color|3|F|--no-color ?',
    '--color|3|F|--color (forcer) ?',
    '--quiet|3|F|--quiet (silence console avec --out) ?',
    '--out|3|V|--out=FICHIER :',
    '--mode|4|V|--mode=alarm :',
    '--pattern|4|V|--pattern=TEXTE (littéral + | * ?) :',
    '--redact|4|V|--redact=email,ipv4,url :',
    '--log-level|4|F|--log-level (compter ERROR/WARN/…) ?',
    '--filter|4|V|--filter=error,warn,… :',
    '--regex-tag|4|V|--regex-tag=PATTERN (ex. PLC[0-9]+) :',
    '--top-tags|4|V|--top-tags=N :',
    '--watch|4|F|--watch (polling, Ctrl+C pour stopper) ?',
    '--follow|4|F|--follow (alias de --watch) ?',
    '--interval|4|V|--interval=N (secondes, défaut 2) :',
    '--check|5|F|--check (mode gate CI) ?',
    '--fail-if|5|V|--fail-if=METRIQUE>SEUIL (ex. words>100) :',
    '--warn-if|5|V|--warn-if=METRIQUE>SEUIL :',
    '--compare|5|V|--compare=BASELINE.ndjson :',
    '--fail-on-delta|5|V|--fail-on-delta=METRIQUE>X% :',
    '--json|6|F|--json ?',
    '--json-mode|6|V|--json-mode=ndjson|array|aggregate :',
    '--summary-json|6|F|--summary-json ?',
    '--csv|6|V|--csv=summary|words|chars :',
    '--version|7|F|--version ?',
    '--help|7|F|--help ?'
  );

procedure InitOpts;
var
  i, P1, P2, P3: Integer;
  S: string;
begin
  CAT_NAMES[1] := 'Fichiers/entrée';
  CAT_NAMES[2] := 'Analyse';
  CAT_NAMES[3] := 'Affichage';
  CAT_NAMES[4] := 'Log Sentinel';
  CAT_NAMES[5] := 'Checks/gate CI';
  CAT_NAMES[6] := 'Export';
  CAT_NAMES[7] := 'Divers';
  for i := 1 to OPT_COUNT do
  begin
    S := OPT_DEFS[i];
    P1 := Pos('|', S); P2 := Pos('|', S, P1 + 1); P3 := Pos('|', S, P2 + 1);
    OPTS[i].Name := Copy(S, 1, P1 - 1);
    OPTS[i].Cat := StrToInt(Copy(S, P1 + 1, P2 - P1 - 1));
    if Copy(S, P2 + 1, 1) = 'F' then OPTS[i].Kind := okFlag else OPTS[i].Kind := okValue;
    OPTS[i].Prompt := Copy(S, P3 + 1, MaxInt);
  end;
end;

function OptAt(Index: Integer): TCmdOpt;
begin
  Result := OPTS[Index];
end;

function CatName(Cat: Integer): string;
begin
  Result := CAT_NAMES[Cat];
end;

function CmdQuote(const S: string): string;
const
  // Métacaractères qui déclenchent le quoting (au-delà de l'espace/tab).
  // Windows : & | < > ^ % ! (cmd.exe). Unix : ; $ ` \ ( ) & * ? [ ] # ~ ! < >
  {$IFDEF MSWINDOWS}
  META: string = '&|<>^%!';
  {$ELSE}
  META: string = ';$`()&*?[]#~!<>';
  {$ENDIF}
var
  NeedsQuote: Boolean;
  i: Integer;
begin
  NeedsQuote := (S = '') or (Pos(' ', S) > 0) or (Pos(#9, S) > 0);
  if not NeedsQuote then
    for i := 1 to Length(META) do
      if Pos(META[i], S) > 0 then
      begin
        NeedsQuote := True;
        Break;
      end;
  if not NeedsQuote then
    Exit(S);
  {$IFDEF MSWINDOWS}
  Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
  {$ELSE}
  Result := '''' + StringReplace(S, '''', '''\''''', [rfReplaceAll]) + '''';
  {$ENDIF}
end;

function BuildCmd(const CmdName: string; const Tokens: TStringList): string;
var
  i: Integer;
begin
  Result := CmdQuote(CmdName);
  for i := 0 to Tokens.Count - 1 do
    Result := Result + ' ' + CmdQuote(Tokens[i]);
end;

function RunArgs(const ExePath: string; const Args: array of string): Integer;
begin
  // v2.14.0 (P1-1) : ExecuteProcess fabrique lui-même l'argv (Unix :
  // fork/execve, Windows : CreateProcess) — aucun shell, aucun parsing de
  // la part de l'OS. Une valeur contenant `; rm -rf` est un simple argument.
  try
    Result := ExecuteProcess(ExePath, Args);
  except
    on E: Exception do
      Result := -1;  // exécutable introuvable/illisible : échec propre
  end;
end;

function RunTokens(const ExePath: string; const Tokens: TStringList): Integer;
var
  A: array of string;
  i: Integer;
begin
  SetLength(A, Tokens.Count);
  for i := 0 to Tokens.Count - 1 do
    A[i] := Tokens[i];
  Result := RunArgs(ExePath, A);
end;

function FindOpt(const Tokens: TStringList; const Name: string): Integer;
var
  i, P: Integer;
begin
  Result := -1;
  for i := 0 to Tokens.Count - 1 do
  begin
    if Name = '' then
    begin
      if (Tokens[i] <> '') and (Tokens[i][1] <> '-') then Exit(i);
    end
    else
    begin
      P := Pos('=', Tokens[i]);
      if ((P > 0) and (Copy(Tokens[i], 1, P - 1) = Name)) or (Tokens[i] = Name) then
        Exit(i);
    end;
  end;
end;

function OptValue(const Tokens: TStringList; const Name: string): string;
var
  i, P: Integer;
begin
  i := FindOpt(Tokens, Name);
  if i < 0 then Exit('');
  if Name = '' then Exit(Tokens[i]);
  P := Pos('=', Tokens[i]);
  if P > 0 then Result := Copy(Tokens[i], P + 1, MaxInt)
  else Result := '1';  // flag présent
end;

procedure SetOpt(const Tokens: TStringList; const Opt: TCmdOpt; const V: string);
var
  i, k: Integer;
  Parts: TStringArray;
begin
  i := FindOpt(Tokens, Opt.Name);
  if Opt.Name = '' then
  begin
    // fichiers positionnels : on retire tous les tokens sans '-' et on remet la liste
    for k := Tokens.Count - 1 downto 0 do
      if (Tokens[k] <> '') and (Tokens[k][1] <> '-') then Tokens.Delete(k);
    if V <> '' then
    begin
      Parts := V.Split([' ']);
      for k := 0 to High(Parts) do
        if Parts[k] <> '' then Tokens.Add(Parts[k]);
    end;
    Exit;
  end;
  if i >= 0 then Tokens.Delete(i);
  if Opt.Kind = okFlag then
  begin
    if V = '1' then Tokens.Add(Opt.Name);
  end
  else if V <> '' then
    Tokens.Add(Opt.Name + '=' + V);
end;

procedure ApplyProfil(Profil: Integer; const Tokens: TStringList);
var
  i: Integer;
begin
  // retire d'abord les options des profils précédents (on garde les fichiers)
  for i := Tokens.Count - 1 downto 0 do
    if (Tokens[i] <> '') and (Tokens[i][1] = '-') then Tokens.Delete(i);
  case Profil of
    1: begin  // corpus : analyse de textes
         SetOpt(Tokens, OPTS[15], '2');             // --ngrams=2 (1..5, un seul N)
         SetOpt(Tokens, OPTS[19], '1');               // --lexical-stats
         SetOpt(Tokens, OPTS[20], '1');               // --readability
         SetOpt(Tokens, OPTS[44], '1');               // --json
       end;
    2: begin  // log : Log Sentinel
         SetOpt(Tokens, OPTS[29], 'alarm');           // --mode=alarm
         SetOpt(Tokens, OPTS[14], '10');              // --top-lines=10
         SetOpt(Tokens, OPTS[31], 'email,ipv4,url');  // --redact
       end;
    3: begin  // gate : quality gate CI
         SetOpt(Tokens, OPTS[39], '1');               // --check
         SetOpt(Tokens, OPTS[44], '1');               // --json
         SetOpt(Tokens, OPTS[46], '1');               // --summary-json
       end;
  end;
end;

procedure PrintCmd(const CmdName: string; const Tokens: TStringList);
begin
  WriteLn('Commande générée :');
  WriteLn('  ' + BuildCmd(CmdName, Tokens));
  WriteLn;
end;

function ReadLineOrEOF(var S: string): Boolean;
begin
  Result := True;
  if EOF(Input) then Exit(False);
  ReadLn(Input, S);
end;

function RunWizard(const CmdName: string; const Tokens: TStringList;
                   PresetProfil: Integer): Boolean;
var
  S: string;
  Profil, Cat, Num, i, P: Integer;
  Opt: TCmdOpt;
begin
  Result := False;
  Tokens.Clear;
  WriteLn('=== fstats cmdgen v', CMDGEN_VERSION, ' — générateur de ligne de commande ===');
  WriteLn;
  if PresetProfil in [1..3] then
    Profil := PresetProfil
  else
  begin
    WriteLn('Profil :');
    WriteLn('  1) corpus  — analyser des textes (mots, n-grams, lisibilité, JSON)');
    WriteLn('  2) log     — Log Sentinel (alarm, patterns, redaction, watch)');
    WriteLn('  3) gate    — quality gate CI (checks, baseline, exit codes)');
    WriteLn('  4) aucun   — partir de zéro');
    Write('Choix [1-4] : ');
    if not ReadLineOrEOF(S) then Exit;
    if not TryStrToInt(Trim(S), Profil) then Profil := 4;
    if Profil = 4 then Profil := 0;
  end;
  if Profil > 0 then ApplyProfil(Profil, Tokens);

  repeat
    PrintCmd(CmdName, Tokens);
    WriteLn('Catégorie : 1=Fichiers 2=Analyse 3=Affichage 4=Sentinel 5=Checks 6=Export 7=Divers  0=terminer');
    Write('> ');
    if not ReadLineOrEOF(S) then Exit;
    if not TryStrToInt(Trim(S), Cat) then Cat := 0;
    if Cat = 0 then Break;
    if (Cat < 1) or (Cat > 7) then Continue;
    // liste les options de la catégorie avec leur état
    WriteLn('--- ', CAT_NAMES[Cat], ' ---');
    for i := 1 to OPT_COUNT do
      if OPTS[i].Cat = Cat then
      begin
        if OPTS[i].Name = '' then
          WriteLn('  [f] fichiers : ', OptValue(Tokens, ''))
        else if FindOpt(Tokens, OPTS[i].Name) >= 0 then
          WriteLn('  [x] ', OPTS[i].Name, ' = ', OptValue(Tokens, OPTS[i].Name))
        else
          WriteLn('  [ ] ', OPTS[i].Name);
      end;
    Write('N° de l''option à éditer (1-', OPT_COUNT, ', f=fichiers, 0=retour) : ');
    if not ReadLineOrEOF(S) then Exit;
    S := Trim(S);
    if (S = '0') or (S = '') then Continue;
    if S = 'f' then Num := 1
    else if not TryStrToInt(S, Num) then Continue;
    if (Num < 1) or (Num > OPT_COUNT) then Continue;
    Opt := OPTS[Num];
    if (Opt.Cat <> Cat) and (Opt.Name <> '') then Continue;  // sécurité
    if Opt.Name = '' then
    begin
      Write(Opt.Prompt, ' [', OptValue(Tokens, ''), '] : ');
      if not ReadLineOrEOF(S) then Exit;
      if Trim(S) = '' then S := OptValue(Tokens, '');
      SetOpt(Tokens, Opt, Trim(S));
    end
    else if Opt.Kind = okFlag then
    begin
      if FindOpt(Tokens, Opt.Name) >= 0 then SetOpt(Tokens, Opt, '')
      else SetOpt(Tokens, Opt, '1');
    end
    else
    begin
      Write(Opt.Prompt, ' [', OptValue(Tokens, Opt.Name), '] (vide = garder, x = retirer) : ');
      if not ReadLineOrEOF(S) then Exit;
      S := Trim(S);
      if S = 'x' then SetOpt(Tokens, Opt, '')
      else if S <> '' then SetOpt(Tokens, Opt, S);
    end;
  until False;

  PrintCmd(CmdName, Tokens);
  Result := True;
end;

initialization
  InitOpts;

end.
