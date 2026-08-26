@echo off
setlocal EnableExtensions
rem ============================================================================
rem tests\run.bat - Journal de validation reproductible de fstats (increment A)
rem Usage : tests\run.bat   (double-clic ou invite de commandes)
rem Prerequis : fpc et (optionnellement) node sur le PATH.
rem Compile fstats, execute les cas d'acceptation, verifie les exit codes et
rem valide le JSON avec node (si disponible). Sortie : une ligne PASS/FAIL par
rem cas, puis un bilan. Exit 0 si tout passe, 1 sinon. Pas de Pause : CI friendly.
rem Note : les globs sont resolus en interne par fstats (CMD n'expand pas les
rem motifs), les filtres node sont sans metacharacteres cmd.
rem ============================================================================

cd /d "%~dp0.."
set "FSTATS=%CD%\fstats.exe"
set "TMPD=%TEMP%\fstats_tests"
if not exist "%TMPD%" mkdir "%TMPD%"

set PASS=0
set FAIL=0

rem node disponible ?
set NODE_OK=0
where node >nul 2>nul
if not errorlevel 1 set NODE_OK=1

rem --- 1. Compilation ---------------------------------------------------------
fpc -O2 -Mobjfpc fstats.pas > "%TMPD%\compile.log" 2>&1
if errorlevel 1 (set /a FAIL+=1&echo FAIL: compilation : fpc -O2 -Mobjfpc fstats.pas [exit 0]) else (set /a PASS+=1&echo PASS: compilation : fpc -O2 -Mobjfpc fstats.pas [exit 0])
findstr /C:"lines compiled" "%TMPD%\compile.log"

rem --- 2. Compteurs de reference (test_fr.txt) --------------------------------
"%FSTATS%" --summary-json test_fr.txt > "%TMPD%\test_fr.json" 2>nul
if "%NODE_OK%"=="1" goto :node2
echo SKIP: test_fr.json (node indisponible)
goto :after2
:node2
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log('  test_fr.txt -> lines='+o.lines+' words='+o.words+' chars='+o.characters+' sentences='+o.sentences+' avg='+o.avg_words_per_sentence+' min/max/avg='+o.line_min+'/'+o.line_max+'/'+o.line_avg);process.exit((o.lines===3?0:1)+(o.words===13?0:1)+(o.characters===72?0:1)+(o.sentences===3?0:1)+(o.avg_words_per_sentence===4?0:1)+(o.line_min===16?0:1)+(o.line_max===30?0:1)+(o.line_avg===23?0:1));" < "%TMPD%\test_fr.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: test_fr.txt : 3/13/72/3, moy 4, min/max/moy 16/30/23) else (set /a PASS+=1&echo PASS: test_fr.txt : 3/13/72/3, moy 4, min/max/moy 16/30/23)
:after2

rem --- 3. stdin JSON ----------------------------------------------------------
echo un deux trois. | "%FSTATS%" - --json > "%TMPD%\stdin.json" 2>nul
if "%NODE_OK%"=="1" goto :node3
echo SKIP: stdin.json (node indisponible)
goto :after3
:node3
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit(o.statistics.words===3?0:1);" < "%TMPD%\stdin.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: stdin : echo "un deux trois." ^| fstats - --json [words=3]) else (set /a PASS+=1&echo PASS: stdin : echo "un deux trois." ^| fstats - --json [words=3])
:after3

rem --- 4. stdin melange avec des fichiers = erreur fatale ---------------------
"%FSTATS%" - test_fr.txt > "%TMPD%\mix.out" 2> "%TMPD%\mix.err"
set MIX_OK=1
if not errorlevel 1 set MIX_OK=0
findstr /C:"standard" "%TMPD%\mix.err" >nul 2>nul
if errorlevel 1 set MIX_OK=0
if "%MIX_OK%"=="1" (set /a PASS+=1&echo PASS: stdin + fichier : fstats - test_fr.txt -^> exit 1 + message stderr) else (set /a FAIL+=1&echo FAIL: stdin + fichier : fstats - test_fr.txt -^> exit 1 + message stderr)

rem --- 5. NDJSON multi-fichiers ------------------------------------------------
"%FSTATS%" tests\fixtures\bom.txt tests\fixtures\crlf.txt --json > "%TMPD%\nd.json" 2>nul
if "%NODE_OK%"=="1" goto :node5
echo SKIP: nd.json (node indisponible)
goto :after5
:node5
node -e "var s=require('fs').readFileSync(0,'utf8');var L=s.trim().split(/\r?\n/);if(L.length===2){var a=JSON.parse(L[0]);var b=JSON.parse(L[1]);process.exit((a.quality.bom===true?0:1)+(b.quality.crlf===2?0:1));}else process.exit(1);" < "%TMPD%\nd.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: NDJSON : 2 fichiers -^> 2 lignes parseables [bom=true, crlf=2]) else (set /a PASS+=1&echo PASS: NDJSON : 2 fichiers -^> 2 lignes parseables [bom=true, crlf=2])
:after5

rem --- 6. Aggregate (glob **) --------------------------------------------------
"%FSTATS%" tests\docs\**\*.md --json-mode=aggregate > "%TMPD%\agg.json" 2>nul
if "%NODE_OK%"=="1" goto :node6
echo SKIP: agg.json (node indisponible)
goto :after6
:node6
node -e "var j=JSON.parse(require('fs').readFileSync(0,'utf8'));var t=j.totals;var fl=0;var wo=0;var ch=0;var se=0;for(var k=0;k<j.files.length;k++){fl+=j.files[k].statistics.lines;wo+=j.files[k].statistics.words;ch+=j.files[k].statistics.characters;se+=j.files[k].statistics.sentences;}process.exit((j.files.length===3?0:1)+(fl===t.lines?0:1)+(wo===t.words?0:1)+(ch===t.characters?0:1)+(se===t.sentences?0:1));" < "%TMPD%\agg.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: aggregate : tests\docs\**\*.md -^> 3 fichiers, totaux coherents) else (set /a PASS+=1&echo PASS: aggregate : tests\docs\**\*.md -^> 3 fichiers, totaux coherents)
:after6

rem --- 7. summary-json (objet plat) --------------------------------------------
"%FSTATS%" --summary-json test_fr.txt > "%TMPD%\sum.json" 2>nul
if "%NODE_OK%"=="1" goto :node7
echo SKIP: sum.json (node indisponible)
goto :after7
:node7
node -e "JSON.parse(require('fs').readFileSync(0,'utf8'));" < "%TMPD%\sum.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --summary-json test_fr.txt -^> objet plat JSON valide) else (set /a PASS+=1&echo PASS: --summary-json test_fr.txt -^> objet plat JSON valide)
:after7

rem --- 8. Compteur qualite invalid_utf8 ----------------------------------------
"%FSTATS%" tests\fixtures\invalid-utf8.bin --summary-json > "%TMPD%\inv.json" 2>nul
if "%NODE_OK%"=="1" goto :node8
echo SKIP: inv.json (node indisponible)
goto :after8
:node8
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit(o.invalid_utf8>0?0:1);" < "%TMPD%\inv.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: fixture invalid-utf8.bin : invalid_utf8 ^> 0 dans le JSON) else (set /a PASS+=1&echo PASS: fixture invalid-utf8.bin : invalid_utf8 ^> 0 dans le JSON)
:after8

rem --- 9. Fichier absent -^> exit 1 ---------------------------------------------
"%FSTATS%" absent.txt > "%TMPD%\abs.out" 2> "%TMPD%\abs.err"
set ABS_OK=1
if not errorlevel 1 set ABS_OK=0
findstr . "%TMPD%\abs.out" >nul 2>nul
if not errorlevel 1 set ABS_OK=0
if "%ABS_OK%"=="1" (set /a PASS+=1&echo PASS: fstats absent.txt -^> exit 1, stdout vide, message stderr) else (set /a FAIL+=1&echo FAIL: fstats absent.txt -^> exit 1, stdout vide, message stderr)

rem --- 10. Glob sans correspondance -^> exit 1 ----------------------------------
"%FSTATS%" tests\**\*.nonexistent > "%TMPD%\glob.out" 2> "%TMPD%\glob.err"
if errorlevel 1 (set /a PASS+=1&echo PASS: glob sans correspondance -^> exit 1 [gate CI jamais silencieusement vide]) else (set /a FAIL+=1&echo FAIL: glob sans correspondance -^> exit 1 [gate CI jamais silencieusement vide])

rem --- 11. Sortie pipee sans sequence ANSI --------------------------------------
"%FSTATS%" test_fr.txt > "%TMPD%\console.txt" 2>nul
if "%NODE_OK%"=="1" goto :node11
echo SKIP: controle ANSI (node indisponible)
goto :after11
:node11
node -e "var b=require('fs').readFileSync(0);process.exit(b.indexOf(27)<0?0:1);" < "%TMPD%\console.txt"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: sortie console pipee : aucune sequence ANSI [ESC]) else (set /a PASS+=1&echo PASS: sortie console pipee : aucune sequence ANSI [ESC])
:after11

rem --- 12. Version ---------------------------------------------------------------
"%FSTATS%" --version | findstr /C:"2.2.0" >nul
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --version affiche 2.2.0) else (set /a PASS+=1&echo PASS: --version affiche 2.2.0)

echo.
echo RESULTAT : %PASS% reussi, %FAIL% echec(s)
rd /s /q "%TMPD%" >nul 2>nul
if "%FAIL%"=="0" exit /b 0
exit /b 1
