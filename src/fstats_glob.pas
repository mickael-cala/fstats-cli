{=============================================================================
  fstats_glob.pas — moteur de glob interne (*, **, ?) et parcours récursif
  =============================================================================}
unit fstats_glob;

{$mode objfpc}
{$H+}

interface

uses
  fstats_types, SysUtils, Classes;

function IsPathSeparator(C: Char): Boolean;
function CharEquals(A, B: Char): Boolean;
function GlobMatch(const P, S: string): Boolean;
function ContainsWildcard(const S: string): Boolean;
function ContainsDoubleStar(const S: string): Boolean;
function NormalizePath(const S: string): string;
function JoinPath(const A, B: string): string;
function ExtractBaseDir(const Pattern: string): string;
procedure WalkAndMatch(const Dir: string; Recurse: Boolean; const Pattern: string;
                       const Results: TStringList; var MatchCount: Integer);
procedure ResolveGlobPattern(const Pattern: string; const Results: TStringList);
procedure CollectRecursive(const Root: string; const IncludeP, ExcludeP: TStringList;
                           MaxDepth: Integer; const Results: TStringList);
procedure QuickSortStrList(L: TStringList; Lo, Hi: Integer);
procedure DedupeSorted(L: TStringList);

implementation

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


end.
