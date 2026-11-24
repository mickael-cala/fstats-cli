@echo off
setlocal
rem ==========================================================================
rem  fstats-cli -- build.bat : compilation Windows multi-cibles (32 + 64 bits)
rem
rem  Cibles   : i386-win32  (natif)      -> bin\win32\fstats.exe + fcmd.exe
rem             x86_64-win64 (cross)     -> bin\win64\fstats.exe + fcmd.exe
rem
rem  Regles   : -Sg est OBLIGATOIRE (goto dans fstats_lex.pas, lecon 13)
rem             une cible indisponible est signalee puis ignoree : le script
rem             continue ; messages ASCII seulement (codepage indifferrent)
rem  Exit     : 0 = toutes les cibles compilees, 1 = au moins un echec
rem  Requis   : Free Pascal 3.2.2+ (fpc dans le PATH, ou chemins connus)
rem ==========================================================================

set "FPC="
set "OK=0"
set "KO=0"

rem -- 1. Localisation du compilateur ---------------------------------------
where fpc >nul 2>&1 && set "FPC=fpc"
if not defined FPC if exist "C:\FPC\3.2.2\bin\i386-Win32\fpc.exe"  set "FPC=C:\FPC\3.2.2\bin\i386-Win32\fpc.exe"
if not defined FPC if exist "C:\FPC\3.2.2\bin\x86_64-w64\fpc.exe"  set "FPC=C:\FPC\3.2.2\bin\x86_64-w64\fpc.exe"
if not defined FPC if exist "C:\tools\freepascal\bin\i386-win32\fpc.exe" set "FPC=C:\tools\freepascal\bin\i386-win32\fpc.exe"
if not defined FPC if exist "C:\lazarus\fpc\3.2.2\bin\i386-win32\fpc.exe" set "FPC=C:\lazarus\fpc\3.2.2\bin\i386-win32\fpc.exe"

if not defined FPC (
    echo [ERREUR] Compilateur Free Pascal introuvable.
    echo          Installez FPC puis relancez, ou editez ce script pour
    echo          indiquer le chemin de fpc.exe.
    exit /b 1
)
echo Compilateur : %FPC%

rem -- 2. Cible 32 bits : i386-win32 (natif) -------------------------------
call :cible "Windows 32 bits (natif i386)"     "-"        "win32"

rem -- 3. Cible 64 bits : x86_64-win64 --------------------------------------
call :cible "Windows 64 bits (cross x86_64)"   "-Px86_64" "win64"

rem -- 4. Recapitulatif ------------------------------------------------------
echo.
if "%KO%"=="0" (
    echo RECAP : 2/2 cibles compilees. Binaires dans bin\win32\ et bin\win64\.
    exit /b 0
)
echo RECAP : %OK% cible(s) compilee(s), %KO% cible(s) en echec -- voir ci-dessus.
exit /b 1

rem ---------------------------------------------------------------------------
:cible
rem %1 = description, %2 = option -P ("-" = natif), %3 = sous-dossier bin
set "DESC=%~1"
set "OPTP=%~2"
set "DIRB=bin\%~3"
if "%OPTP%"=="-" set "OPTP="
if not exist "%DIRB%\" mkdir "%DIRB%"

echo.
echo === %DESC% ===
echo     sortie : %DIRB%\

"%FPC%" %OPTP% -Sg -O2 -Mobjfpc -FE"%DIRB%" -FU"%DIRB%" src\fstats.pas
if errorlevel 1 goto :rate
"%FPC%" %OPTP% -Sg -O2 -Mobjfpc -FE"%DIRB%" -FU"%DIRB%" src\fcmd.pas
if errorlevel 1 goto :rate

echo     CIBLE OK : %DIRB%\fstats.exe + %DIRB%\fcmd.exe
set /a OK+=1
goto :eof

:rate
echo.
echo     [ECHEC ] %DESC% : compilateur ou unites indisponibles pour cette
echo     cible. Pour la cible 64 bits, il faut une installation FPC incluant
echo     la cible x86_64-win64. Les autres cibles continuent.
rmdir "%DIRB%" 2>nul
set /a KO+=1
goto :eof
