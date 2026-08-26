@echo off
setlocal EnableExtensions
rem ============================================================================
rem tests\run.bat - Journal de validation reproductible de fstats
rem (increments A + C2-A "Lexique", v2.3.0)
rem Usage : tests\run.bat   (double-clic ou invite de commandes)
rem Prerequis : fpc et (optionnellement) node sur le PATH.
rem Compile fstats, execute les cas d'acceptation, verifie les exit codes et
rem valide le JSON avec node (si disponible). Sortie : une ligne PASS/FAIL par
rem cas, puis un bilan. Exit 0 si tout passe, 1 sinon. Pas de Pause : CI friendly.
rem Note : les globs sont resolus en interne par fstats (CMD n'expand pas les
rem motifs), les filtres node sont sans metacaracteres cmd.
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
fpc -O2 -Mobjfpc -FE. src\fstats.pas > "%TMPD%\compile.log" 2>&1
if errorlevel 1 (set /a FAIL+=1&echo FAIL: compilation : fpc -O2 -Mobjfpc -FE. src\fstats.pas [exit 0]) else (set /a PASS+=1&echo PASS: compilation : fpc -O2 -Mobjfpc -FE. src\fstats.pas [exit 0])
findstr /C:"lines compiled" "%TMPD%\compile.log"

rem --- 2. Compteurs de reference (tests\fixtures\test_fr.txt) -----------------
"%FSTATS%" --summary-json tests\fixtures\test_fr.txt > "%TMPD%\test_fr.json" 2>nul
if "%NODE_OK%"=="1" goto :node2
echo SKIP: test_fr.json (node indisponible)
goto :after2
:node2
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log('  tests\\fixtures\\test_fr.txt -> lines='+o.lines+' words='+o.words+' chars='+o.characters+' sentences='+o.sentences+' avg='+o.avg_words_per_sentence+' min/max/avg='+o.line_min+'/'+o.line_max+'/'+o.line_avg);process.exit((o.lines===3?0:1)+(o.words===13?0:1)+(o.characters===72?0:1)+(o.sentences===3?0:1)+(o.avg_words_per_sentence===4?0:1)+(o.line_min===16?0:1)+(o.line_max===30?0:1)+(o.line_avg===23?0:1));" < "%TMPD%\test_fr.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: tests\fixtures\test_fr.txt : 3/13/72/3, moy 4, min/max/moy 16/30/23) else (set /a PASS+=1&echo PASS: tests\fixtures\test_fr.txt : 3/13/72/3, moy 4, min/max/moy 16/30/23)
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
"%FSTATS%" - tests\fixtures\test_fr.txt > "%TMPD%\mix.out" 2> "%TMPD%\mix.err"
set MIX_OK=1
if not errorlevel 1 set MIX_OK=0
findstr /C:"standard" "%TMPD%\mix.err" >nul 2>nul
if errorlevel 1 set MIX_OK=0
if "%MIX_OK%"=="1" (set /a PASS+=1&echo PASS: stdin + fichier : fstats - tests\fixtures\test_fr.txt -^> exit 1 + message stderr) else (set /a FAIL+=1&echo FAIL: stdin + fichier : fstats - tests\fixtures\test_fr.txt -^> exit 1 + message stderr)

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
"%FSTATS%" --summary-json tests\fixtures\test_fr.txt > "%TMPD%\sum.json" 2>nul
if "%NODE_OK%"=="1" goto :node7
echo SKIP: sum.json (node indisponible)
goto :after7
:node7
node -e "JSON.parse(require('fs').readFileSync(0,'utf8'));" < "%TMPD%\sum.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --summary-json tests\fixtures\test_fr.txt -^> objet plat JSON valide) else (set /a PASS+=1&echo PASS: --summary-json tests\fixtures\test_fr.txt -^> objet plat JSON valide)
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
"%FSTATS%" tests\fixtures\test_fr.txt > "%TMPD%\console.txt" 2>nul
if "%NODE_OK%"=="1" goto :node11
echo SKIP: controle ANSI (node indisponible)
goto :after11
:node11
node -e "var b=require('fs').readFileSync(0);process.exit(b.indexOf(27)<0?0:1);" < "%TMPD%\console.txt"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: sortie console pipee : aucune sequence ANSI [ESC]) else (set /a PASS+=1&echo PASS: sortie console pipee : aucune sequence ANSI [ESC])
:after11

rem --- 12. Version ---------------------------------------------------------------
"%FSTATS%" --version | findstr /C:"2.3.0" >nul
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --version affiche 2.3.0) else (set /a PASS+=1&echo PASS: --version affiche 2.3.0)

rem --- 13. word-mode=ascii (corpus EN, ponctuation) ------------------------------
"%FSTATS%" --summary-json --word-mode=ascii tests\fixtures\corpus_en.txt > "%TMPD%\ascii.json" 2>nul
if "%NODE_OK%"=="1" goto :node13
echo SKIP: ascii.json (node indisponible)
goto :after13
:node13
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit(o.words===11?0:1);" < "%TMPD%\ascii.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --word-mode=ascii corpus_en.txt -^> words=11 [golden]) else (set /a PASS+=1&echo PASS: --word-mode=ascii corpus_en.txt -^> words=11 [golden])
:after13

rem --- 14. casefold=unicode (corpus FR accentue) ---------------------------------
"%FSTATS%" --summary-json --lexical-stats --casefold=unicode tests\fixtures\corpus_fr.txt > "%TMPD%\cfuni.json" 2>nul
if "%NODE_OK%"=="1" goto :node14
echo SKIP: cfuni.json (node indisponible)
goto :after14
:node14
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit((o.unique_words===16?0:1)+(o.words===20?0:1));" < "%TMPD%\cfuni.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --casefold=unicode corpus_fr.txt -^> unique_words=16, words=20) else (set /a PASS+=1&echo PASS: --casefold=unicode corpus_fr.txt -^> unique_words=16, words=20)
:after14

rem --- 15. casefold=none (casse conservee) ---------------------------------------
"%FSTATS%" --summary-json --lexical-stats --casefold=none tests\fixtures\corpus_fr.txt > "%TMPD%\cfnone.json" 2>nul
if "%NODE_OK%"=="1" goto :node15
echo SKIP: cfnone.json (node indisponible)
goto :after15
:node15
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit((o.unique_words===17?0:1)+(o.words===20?0:1));" < "%TMPD%\cfnone.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --casefold=none corpus_fr.txt -^> unique_words=17, casse conservee) else (set /a PASS+=1&echo PASS: --casefold=none corpus_fr.txt -^> unique_words=17, casse conservee)
:after15

rem --- 16. --lexical-stats (JSON) ------------------------------------------------
"%FSTATS%" --json --lexical-stats tests\fixtures\test_fr.txt > "%TMPD%\lex.json" 2>nul
if "%NODE_OK%"=="1" goto :node16
echo SKIP: lex.json (node indisponible)
goto :after16
:node16
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var l=o.lexical;process.exit((l.unique_words===12?0:1)+(l.hapax===11?0:1)+(l.average_word_length>0?0:1)+(Math.abs(l.type_token_ratio-l.unique_words/o.statistics.words)<1e-4?0:1)+((l.entropy_bits_per_word>=0)*(l.entropy_bits_per_word<=Math.log2(l.unique_words)+1e-9)?0:1));" < "%TMPD%\lex.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --lexical-stats : champs presents, TTR=types/tokens, entropie bornee) else (set /a PASS+=1&echo PASS: --lexical-stats : champs presents, TTR=types/tokens, entropie bornee)
:after16

rem --- 17. --top-words=5 / --top-chars=3 -----------------------------------------
"%FSTATS%" --json --top-words=5 --top-chars=3 tests\fixtures\test_fr.txt > "%TMPD%\top.json" 2>nul
if "%NODE_OK%"=="1" goto :node17
echo SKIP: top.json (node indisponible)
goto :after17
:node17
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit((o.top_words.length===5?0:1)+(o.top_characters.length===3?0:1));" < "%TMPD%\top.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --top-words=5 --top-chars=3 -^> exactement 5 et 3 entrees) else (set /a PASS+=1&echo PASS: --top-words=5 --top-chars=3 -^> exactement 5 et 3 entrees)
:after17

rem --- 18. --top-words=0 = --all (section mots) ----------------------------------
"%FSTATS%" --json --top-words=0 tests\fixtures\test_fr.txt > "%TMPD%\top0.json" 2>nul
if "%NODE_OK%"=="1" goto :node18
echo SKIP: top0.json (node indisponible)
goto :after18
:node18
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit(o.top_words.length===12?0:1);" < "%TMPD%\top0.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --top-words=0 -^> tous les mots, 12 pour test_fr.txt) else (set /a PASS+=1&echo PASS: --top-words=0 -^> tous les mots, 12 pour test_fr.txt)
:after18

rem --- 19. --max-unique (borne memoire) ------------------------------------------
"%FSTATS%" --summary-json --lexical-stats --max-unique=5 tests\fixtures\test_fr.txt > "%TMPD%\mu.json" 2>nul
if "%NODE_OK%"=="1" goto :node19
echo SKIP: mu.json (node indisponible)
goto :after19
:node19
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit((o.unique_words===5?0:1)+(o.words===13?0:1));" < "%TMPD%\mu.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --max-unique=5 -^> unique_words plafonne a 5, words=13 inchange) else (set /a PASS+=1&echo PASS: --max-unique=5 -^> unique_words plafonne a 5, words=13 inchange)
:after19

rem --- 20. CSV v2 (en-tete + ligne summary + csv=words) --------------------------
"%FSTATS%" --csv tests\fixtures\test_fr.txt > "%TMPD%\csv2.csv" 2>nul
"%FSTATS%" --csv=words tests\fixtures\test_fr.txt > "%TMPD%\csv2w.csv" 2>nul
if "%NODE_OK%"=="1" goto :node20
echo SKIP: CSV v2 (node indisponible)
goto :after20
:node20
node -e "var fs=require('fs');var s=fs.readFileSync(process.argv[1],'utf8');var w=fs.readFileSync(process.argv[2],'utf8');var L=s.trim().split(/\r?\n/);var H='file,type,rank,value,code_point,count,length';var okS=L.slice(1).some(function(r){var c=r.split(',');return c[1]==='summary'&&c[3]==='lines'&&c[5]==='3'&&c[0].indexOf('test_fr.txt')>=0;});var W=w.trim().split(/\r?\n/);process.exit((L[0]===H&&okS&&W[0]===H&&W.length===11)?0:1);" "%TMPD%\csv2.csv" "%TMPD%\csv2w.csv"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: CSV v2 : en-tete exact, ligne summary avec colonne file, csv=words 10 lignes) else (set /a PASS+=1&echo PASS: CSV v2 : en-tete exact, ligne summary avec colonne file, csv=words 10 lignes)
:after20

rem --- 21. word-mode=unicode (corpus FR) -----------------------------------------
"%FSTATS%" --summary-json --word-mode=unicode tests\fixtures\corpus_fr.txt > "%TMPD%\uni.json" 2>nul
if "%NODE_OK%"=="1" goto :node21
echo SKIP: uni.json (node indisponible)
goto :after21
:node21
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit(o.words===19?0:1);" < "%TMPD%\uni.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --word-mode=unicode corpus_fr.txt -^> words=19 [golden]) else (set /a PASS+=1&echo PASS: --word-mode=unicode corpus_fr.txt -^> words=19 [golden])
:after21

rem --- 22. Option lexicale invalide -^> exit 1 -----------------------------------
"%FSTATS%" --word-mode=bogus tests\fixtures\test_fr.txt > "%TMPD%\bad.out" 2> "%TMPD%\bad.err"
set BAD_OK=1
if not errorlevel 1 set BAD_OK=0
findstr /C:"word-mode" "%TMPD%\bad.err" >nul 2>nul
if errorlevel 1 set BAD_OK=0
if "%BAD_OK%"=="1" (set /a PASS+=1&echo PASS: --word-mode=bogus -^> exit 1 + message stderr) else (set /a FAIL+=1&echo FAIL: --word-mode=bogus -^> exit 1 + message stderr)

echo.
echo RESULTAT : %PASS% reussi, %FAIL% echec(s)
rd /s /q "%TMPD%" >nul 2>nul
if "%FAIL%"=="0" exit /b 0
exit /b 1
