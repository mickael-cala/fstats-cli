{=============================================================================
  fstats_utf8.pas — utilitaires UTF-8, visualisation, tris, couleurs ANSI
  =============================================================================}
unit fstats_utf8;

{$mode objfpc}
{$H+}

interface

uses
  fstats_types, SysUtils, Classes
  {$IFDEF MSWINDOWS}, Windows{$ENDIF}
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

function UTF8SeqLen(B: Byte): Integer;
function UTF8Length(const S: string): Integer;
function UTF8SafeCopy(const S: string; MaxChars: Integer): string;
function UTF8PadRight(const S: string; Width: Integer): string;
function RepeatString(const S: string; Count: Integer): string;
procedure QuickSortChars(var A: TCharFreqArray; L, R: Integer);
procedure QuickSortWords(var A: TWordFreqArray; L, R: Integer);
procedure QuickSortLines(var A: TLineArray; L, R: Integer);
function OutputIsConsole: Boolean;
function AnsiColor(const Code: Integer): string;
function AnsiReset: string;
function CurrentStamp: string;
function VisualChar(CP: UInt32): string;
function UnicodeCode(CP: UInt32): string;
function DecodeUTF8(const Buf: PByte; Len: Integer; out CP: UInt32; out Used: Integer): Boolean;
procedure AddLine(var Arr: TLineArray; const S: string; Len: Int64; MaxLines: Integer);
function FormatFloatTrim(V: Double; Decimals: Integer): string;

implementation

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


end.
