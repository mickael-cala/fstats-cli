{=============================================================================
  fstats_sha.pas — SHA-256 (FIPS 180-4) pour l'intégrité des baselines
  ============================================================================}
unit fstats_sha;

{$IFDEF FPC}
  {$MODE OBJFPC}
{$ENDIF}

{-----------------------------------------------------------------------------
  Périmètre (audit P2 vague 3, registre sécurité ANTI-INJECTION) :
  - FileSHA256 : SHA-256 du CONTENU du fichier, lu en streaming (64 Ko par
    bloc, mémoire bornée — un fichier de 4 Go ne charge jamais en mémoire).
  - Sha256Hex  : hash d'un buffer mémoire (usage interne/tests).
  - Vérifié   : contre `sha256sum` (GNU coreutils) et le vecteur FIPS
    "abc" -> ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
    (test dédié dans run.sh/run.bat, la parité est re-vérifiable par tout
    un chacun avec sha256sum).
  Usage : clé additive "sha256" du --summary-json (baseline) + vérification
  au --compare (écart -> check sha256 FAIL, cf. SEMANTIQUE.md).
  -----------------------------------------------------------------------------}

interface

function FileSHA256(const Path: string): string;
function Sha256Hex(const Buf; BufLen: Integer): string;

implementation

uses
  SysUtils, Classes;

const
  SHA_BLOCK = 64;         // 512 bits
  SHA_CHUNK = 65536;       // lecture disque (cohérent avec BUF_SIZE)

  // Constantes K (FIPS 180-4, table 4) — cubes des premiers 64 entiers,
  // 32 premiers bits fractionnaires, little-endian stocké ici en valeur.
  SHA_K: array[0..63] of UInt32 = (
    $428A2F98, $71374491, $B5C0FBCF, $E9B5DBA5, $3956C25B, $59F111F1, $923F82A4, $AB1C5ED5,
    $D807AA98, $12835B01, $243185BE, $550C7DC3, $72BE5D74, $80DEB1FE, $9BDC06A7, $C19BF174,
    $E49B69C1, $EFBE4786, $0FC19DC6, $240CA1CC, $2DE92C6F, $4A7484AA, $5CB0A9DC, $76F988DA,
    $983E5152, $A831C66D, $B00327C8, $BF597FC7, $C6E00BF3, $D5A79147, $06CA6351, $14292967,
    $27B70A85, $2E1B2138, $4D2C6DFC, $53380D13, $650A7354, $766A0ABB, $81C2C92E, $92722C85,
    $A2BFE8A1, $A81A664B, $C24B8B70, $C76C51A3, $D192E819, $D6990624, $F40E3585, $106AA070,
    $19A4C116, $1E376C08, $2748774C, $34B0BCB5, $391C0CB3, $4ED8AA4A, $5B9CCA4F, $682E6FF3,
    $748F82EE, $78A5636F, $84C87814, $8CC70208, $90BEFFFA, $A4506CEB, $BEF9A3F7, $C67178F2
  );

type
  TSHAState = record
    H: array[0..7] of UInt32;          // registres d'état
    Buf: array[0..SHA_BLOCK - 1] of Byte;  // bloc incomplet en attente
    BufLen: Integer;                    // octets valides dans Buf
    TotalLen: UInt64;                   // total des octets hashés
  end;

procedure ShaInit(var S: TSHAState);
begin
  // Valeurs initiales (FIPS 180-4, section 5.3.3)
  S.H[0] := $6A09E667; S.H[1] := $BB67AE85; S.H[2] := $3C6EF372; S.H[3] := $A54FF53A;
  S.H[4] := $510E527F; S.H[5] := $9B05688C; S.H[6] := $1F83D9AB; S.H[7] := $5BE0CD19;
  S.BufLen := 0;
  S.TotalLen := 0;
end;

// Rotation 32 bits à droite (ROTR)
function RotR(X: UInt32; N: Integer): UInt32; inline;
begin
  Result := (X shr N) or (X shl (32 - N));
end;

// Compression d'un bloc complet de 64 octets (FIPS 180-4, 6.2.2)
procedure ShaCompressBlock(var S: TSHAState; const Block);
var
  W: array[0..63] of UInt32;
  Blk: array[0..SHA_BLOCK - 1] of Byte;
  i: Integer;
  a, b, c, d, e, f, g, h: UInt32;
  t1, t2, S0, S1, maj, ch: UInt32;
begin
  Move(Block, Blk, SHA_BLOCK);
  // Message schedule : 16 mots big-endian, puis extension
  for i := 0 to 15 do
    W[i] := (UInt32(Blk[i * 4]) shl 24) or (UInt32(Blk[i * 4 + 1]) shl 16) or
            (UInt32(Blk[i * 4 + 2]) shl 8) or UInt32(Blk[i * 4 + 3]);
  for i := 16 to 63 do
  begin
    S0 := RotR(W[i - 15], 7) xor RotR(W[i - 15], 18) xor (W[i - 15] shr 3);
    S1 := RotR(W[i - 2], 17) xor RotR(W[i - 2], 19) xor (W[i - 2] shr 10);
    W[i] := W[i - 16] + S0 + W[i - 7] + S1;
  end;
  a := S.H[0]; b := S.H[1]; c := S.H[2]; d := S.H[3];
  e := S.H[4]; f := S.H[5]; g := S.H[6]; h := S.H[7];
  for i := 0 to 63 do
  begin
    S1 := RotR(e, 6) xor RotR(e, 11) xor RotR(e, 25);
    ch := (e and f) xor ((not e) and g);
    t1 := h + S1 + ch + SHA_K[i] + W[i];
    S0 := RotR(a, 2) xor RotR(a, 13) xor RotR(a, 22);
    maj := (a and b) xor (a and c) xor (b and c);
    t2 := S0 + maj;
    h := g; g := f; f := e; e := d + t1;
    d := c; c := b; b := a; a := t1 + t2;
  end;
  S.H[0] := S.H[0] + a; S.H[1] := S.H[1] + b; S.H[2] := S.H[2] + c; S.H[3] := S.H[3] + d;
  S.H[4] := S.H[4] + e; S.H[5] := S.H[5] + f; S.H[6] := S.H[6] + g; S.H[7] := S.H[7] + h;
end;

procedure ShaUpdate(var S: TSHAState; const Data; DataLen: Integer);
var
  P: ^Byte;
  CopyLen, Remain: Integer;
begin
  if DataLen <= 0 then Exit;
  S.TotalLen := S.TotalLen + UInt64(DataLen);
  P := @Data;
  Remain := DataLen;
  // Compléter le bloc en attente
  if S.BufLen > 0 then
  begin
    CopyLen := SHA_BLOCK - S.BufLen;
    if CopyLen > Remain then CopyLen := Remain;
    Move(P^, S.Buf[S.BufLen], CopyLen);
    Inc(S.BufLen, CopyLen);
    Inc(P, CopyLen);
    Dec(Remain, CopyLen);
    if S.BufLen = SHA_BLOCK then
    begin
      ShaCompressBlock(S, S.Buf);
      S.BufLen := 0;
    end;
  end;
  // Blocs complets directs
  while Remain >= SHA_BLOCK do
  begin
    ShaCompressBlock(S, P^);
    Inc(P, SHA_BLOCK);
    Dec(Remain, SHA_BLOCK);
  end;
  // Reste dans le tampon
  if Remain > 0 then
  begin
    Move(P^, S.Buf, Remain);
    S.BufLen := Remain;
  end;
end;

function ShaFinalHex(var S: TSHAState): string;
var
  PadLen, i, CopyLen: Integer;
  BitLen: UInt64;
  Pad: array[0..79] of Byte;  // 1..64 octets de padding + 8 de longueur
begin
  BitLen := S.TotalLen * 8;
  // Padding : 0x80 puis des zéros, longueur 64 bits big-endian à la fin
  FillChar(Pad, SizeOf(Pad), 0);
  Pad[0] := $80;
  if S.BufLen + 9 <= SHA_BLOCK then
    PadLen := SHA_BLOCK - S.BufLen
  else
    PadLen := 2 * SHA_BLOCK - S.BufLen;
  // La longueur occupe les 8 derniers octets du padding (big-endian)
  for i := 0 to 7 do
    Pad[PadLen - 1 - i] := Byte((BitLen shr (8 * i)) and $FF);
  ShaUpdate(S, Pad[0], PadLen);
  if S.BufLen <> 0 then
  begin
    // garde défensive : ne doit jamais arriver (padding multiple de 64)
    CopyLen := SHA_BLOCK - S.BufLen;
    FillChar(S.Buf[S.BufLen], CopyLen, 0);
    ShaCompressBlock(S, S.Buf);
  end;
  // Sortie hexadécimale minuscule
  Result := '';
  for i := 0 to 7 do
    Result := Result + LowerCase(IntToHex(S.H[i], 8));
end;

function Sha256Hex(const Buf; BufLen: Integer): string;
var
  S: TSHAState;
begin
  ShaInit(S);
  ShaUpdate(S, Buf, BufLen);
  Result := ShaFinalHex(S);
end;

function FileSHA256(const Path: string): string;
var
  S: TSHAState;
  FS: TFileStream;
  Chunk: array[0..SHA_CHUNK - 1] of Byte;
  N: Integer;
begin
  Result := '';
  ShaInit(S);
  try
    FS := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  except
    Exit;   // fichier illisible -> hash vide, l'appelant saute la vérification
  end;
  try
    repeat
      N := FS.Read(Chunk, SHA_CHUNK);
      if N > 0 then
        ShaUpdate(S, Chunk, N);
    until N <= 0;
  finally
    FS.Free;
  end;
  Result := ShaFinalHex(S);
end;

end.
