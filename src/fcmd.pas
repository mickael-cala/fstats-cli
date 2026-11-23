{=============================================================================
  fcmd.pas — compagnon de fstats : génère la ligne de commande (v2.13.0)
  =============================================================================
  Usage :
    fcmd                  wizard interactif, puis demande avant d'exécuter
    fcmd --dry-run        n'affiche que la commande (à copier-coller)
    fcmd --exec           exécute sans demander
    fcmd --profil=N       pré-sélectionne le profil (1=corpus 2=log 3=gate)
    fcmd --help

  Le wizard est pilotable en pipe (lecture ligne par ligne sur stdin) :
    printf '2\n0\n' | fcmd --dry-run
  =============================================================================}
{$codepage utf8}  // Source UTF-8
program fcmd;

{$mode objfpc}
{$H+}

uses
  SysUtils, Classes, fstats_cmdgen
  {$IFDEF MSWINDOWS}, Windows{$ENDIF};

var
  Tokens: TStringList;
  DryRun, Exec, DoHelp: Boolean;
  Profil, i: Integer;
  Param, V: string;
  FstatsPath, Cmd: string;
  S: string;
  ExitCode: Integer;

begin
  Tokens := TStringList.Create;
  try
    DryRun := False;
    Exec := False;
    DoHelp := False;
    Profil := 0;
    for i := 1 to ParamCount do
    begin
      Param := ParamStr(i);
      if (Param = '--help') or (Param = '-h') then DoHelp := True
      else if Param = '--dry-run' then DryRun := True
      else if Param = '--exec' then Exec := True
      else if (Copy(Param, 1, 9) = '--profil=') then
      begin
        V := LowerCase(Copy(Param, 10, MaxInt));
        if not TryStrToInt(V, Profil) then
        begin
          // v2.13.1 : les noms promis par le README sont acceptés
          if V = 'corpus' then Profil := 1
          else if V = 'log' then Profil := 2
          else if V = 'gate' then Profil := 3
          else Profil := 0;
        end;
      end;
    end;

    if DoHelp then
    begin
      WriteLn('fcmd v', CMDGEN_VERSION, ' — compagnon de fstats : génère la ligne de commande.');
      WriteLn;
      WriteLn('Usage :');
      WriteLn('  fcmd                 wizard interactif, puis demande avant d''exécuter');
      WriteLn('  fcmd --dry-run       affiche seulement la commande (copier-coller)');
      WriteLn('  fcmd --exec          exécute sans demander');
      WriteLn('  fcmd --profil=N      preset : 1=corpus 2=log 3=gate');
      WriteLn('  fcmd --help          cette aide');
      WriteLn;
      WriteLn('Exemple pipe :  printf ''2\n0\n'' | fcmd --dry-run');
      Halt(0);
    end;

    if not RunWizard('fstats', Tokens, Profil) then
    begin
      WriteLn(ErrOutput, 'fcmd: entrée interrompue (EOF), aucune commande générée.');
      Halt(1);
    end;

    if DryRun then Halt(0);

    // trouver fstats à côté de fcmd
    {$IFDEF MSWINDOWS}
    FstatsPath := ExtractFilePath(ParamStr(0)) + 'fstats.exe';
    {$ELSE}
    FstatsPath := ExtractFilePath(ParamStr(0)) + 'fstats';
    {$ENDIF}
    if not FileExists(FstatsPath) then
      FstatsPath := 'fstats';  // fallback PATH

    Cmd := BuildCmd(FstatsPath, Tokens);

    if Exec then
    begin
      WriteLn('Exécution : ', Cmd);
      ExitCode := RunAndWait(Cmd);
      Halt(ExitCode);
    end;

    Write('Exécuter cette commande ? [o/N] : ');
    if EOF(Input) then
    begin
      WriteLn(ErrOutput, 'fcmd: EOF — commande non exécutée (utilisez --exec pour forcer).');
      Halt(0);
    end;
    ReadLn(Input, S);
    if LowerCase(Trim(S)) = 'o' then
    begin
      WriteLn('Exécution : ', Cmd);
      ExitCode := RunAndWait(Cmd);
      Halt(ExitCode);
    end;
    WriteLn('Commande non exécutée. À copier-coller :');
    WriteLn('  ' + BuildCmd('fstats', Tokens));
    Halt(0);
  finally
    Tokens.Free;
  end;
end.
