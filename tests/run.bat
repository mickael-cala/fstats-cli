@echo off
setlocal EnableExtensions
rem ============================================================================
rem tests\run.bat - Journal de validation reproductible de fstats
rem (increments A + C2-A "Lexique" + C2-B "Structure" + C2-C "Lisibilite"
rem + Cible 1 B "Checks" + Cible 1 C "Baseline", v2.6.0)
rem Usage : tests\run.bat   (double-clic ou invite de commandes)
rem Prerequis : fpc et (optionnellement) node sur le PATH.
rem Compile fstats, execute les cas d'acceptation, verifie les exit codes et
rem valide le JSON avec node (si disponible). Sortie : une ligne PASS/FAIL par
rem cas, puis un bilan. Exit 0 si tout passe, 1 sinon. Pas de Pause : CI friendly.
rem Note : les globs sont resolus en interne par fstats (CMD n'expand pas les
rem motifs), les filtres node sont sans metacaracteres cmd. Ce fichier reste en
rem ASCII pur (aucun accent) pour un encodage deterministe en CI.
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
if errorlevel 1 (set /a FAIL+=1&echo FAIL: compilation : fpc -O2 -Mobjfpc -FE. src\fstats.pas [errorlevel %ERRORLEVEL%]&type "%TMPD%\compile.log") else (set /a PASS+=1&echo PASS: compilation : fpc -O2 -Mobjfpc -FE. src\fstats.pas [errorlevel %ERRORLEVEL%])
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
if "%NODE_OK%"=="1" goto :node4b
set MIX_OK=1
goto :after4b
:node4b
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['-','tests/fixtures/test_fr.txt'],{encoding:'utf8'});if(r.status===1&&/standard/.test(r.stderr)){process.exit(0);}console.error('[cas4] exit='+r.status+' stdout='+JSON.stringify(r.stdout)+' stderr='+JSON.stringify(r.stderr));process.exit(1);" "%FSTATS%"
if errorlevel 1 (set MIX_OK=0) else (set MIX_OK=1)
:after4b
if "%MIX_OK%"=="1" (set /a PASS+=1&echo PASS: stdin + fichier : fstats - tests\fixtures\test_fr.txt -^> exit 1 + message stderr) else (set /a FAIL+=1&echo FAIL: stdin + fichier : fstats - tests\fixtures\test_fr.txt -^> exit 1 + message stderr)

rem --- 5. NDJSON multi-fichiers ------------------------------------------------
"%FSTATS%" tests\fixtures\bom.txt tests\fixtures\crlf.txt --json > "%TMPD%\nd.json" 2>nul
if "%NODE_OK%"=="1" goto :node5
echo SKIP: nd.json (node indisponible)
goto :after5
:node5
node -e "var s=require('fs').readFileSync(0,'utf8');var L=s.trim().split(/\r?\n/);if(L.length!==2){console.error('nd.json: '+L.length+' ligne(s), attendu 2');process.exit(1);}var a=JSON.parse(L[0]);var b=JSON.parse(L[1]);console.error('nd.json: bom='+a.quality.bom+' crlf='+b.quality.crlf+' (attendu true/2)');process.exit((a.quality.bom===true?0:1)+(b.quality.crlf===2?0:1));" < "%TMPD%\nd.json"
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
if "%NODE_OK%"=="1" goto :node9b
set ABS_OK=1
goto :after9b
:node9b
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['absent.txt'],{encoding:'utf8'});if(r.status===1&&r.stdout===''&&r.stderr.length>0){process.exit(0);}console.error('[cas9] exit='+r.status+' stdout='+JSON.stringify(r.stdout)+' stderr='+JSON.stringify(r.stderr));process.exit(1);" "%FSTATS%"
if errorlevel 1 (set ABS_OK=0) else (set ABS_OK=1)
:after9b
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
"%FSTATS%" --version | findstr /C:"2.6.0" >nul
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --version affiche 2.6.0) else (set /a PASS+=1&echo PASS: --version affiche 2.6.0)

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
if "%NODE_OK%"=="1" goto :node22b
set BAD_OK=1
goto :after22b
:node22b
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--word-mode=bogus','tests/fixtures/test_fr.txt'],{encoding:'utf8'});if(r.status===1&&/word-mode/.test(r.stderr)){process.exit(0);}console.error('[cas22] exit='+r.status+' stdout='+JSON.stringify(r.stdout)+' stderr='+JSON.stringify(r.stderr));process.exit(1);" "%FSTATS%"
if errorlevel 1 (set BAD_OK=0) else (set BAD_OK=1)
:after22b
if "%BAD_OK%"=="1" (set /a PASS+=1&echo PASS: --word-mode=bogus -^> exit 1 + message stderr) else (set /a FAIL+=1&echo FAIL: --word-mode=bogus -^> exit 1 + message stderr)

rem --- 23. ngrams=2 corpus_en (golden, fenetres par ligne) ---------------------
"%FSTATS%" --json --ngrams=2 --word-mode=ascii tests\fixtures\corpus_en.txt > "%TMPD%\ng2.json" 2>nul
if "%NODE_OK%"=="1" goto :node23
echo SKIP: ng2.json (node indisponible)
goto :after23
:node23
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var n=o.ngrams;var has=function(a){return n.some(function(e){return e.words.length===2&&e.words[0]===a[0]&&e.words[1]===a[1];});};process.exit((n.length===9?0:1)+(n.every(function(e){return e.count===1;})?0:1)+(has(['hello','world'])?0:1)+(has(['test','one'])?1:0));" < "%TMPD%\ng2.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --ngrams=2 --word-mode=ascii corpus_en.txt -^> 9 bigrammes, pas de [test one]) else (set /a PASS+=1&echo PASS: --ngrams=2 --word-mode=ascii corpus_en.txt -^> 9 bigrammes, pas de [test one])
:after23

rem --- 24. ngram_lines.txt : pas de traversee des sauts de ligne ---------------
"%FSTATS%" --json --ngrams=2 tests\fixtures\ngram_lines.txt > "%TMPD%\ngl.json" 2>nul
if "%NODE_OK%"=="1" goto :node24
echo SKIP: ngl.json (node indisponible)
goto :after24
:node24
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var n=o.ngrams;var has=function(a){return n.some(function(e){return e.words.length===2&&e.words[0]===a[0]&&e.words[1]===a[1];});};process.exit((n.length===2?0:1)+(has(['alpha','beta'])?0:1)+(has(['gamma','delta'])?0:1)+(has(['beta','gamma'])?1:0));" < "%TMPD%\ngl.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: ngram_lines.txt -^> 2 bigrammes, pas de [beta gamma]) else (set /a PASS+=1&echo PASS: ngram_lines.txt -^> 2 bigrammes, pas de [beta gamma])
:after24

rem --- 25. ngrams=3 top-ngrams=2 -^> exactement 2 entrees ----------------------
"%FSTATS%" --json --ngrams=3 --top-ngrams=2 tests\fixtures\test_fr.txt > "%TMPD%\ng3.json" 2>nul
if "%NODE_OK%"=="1" goto :node25
echo SKIP: ng3.json (node indisponible)
goto :after25
:node25
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit(o.ngrams.length===2?0:1);" < "%TMPD%\ng3.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --ngrams=3 --top-ngrams=2 -^> exactement 2 entrees) else (set /a PASS+=1&echo PASS: --ngrams=3 --top-ngrams=2 -^> exactement 2 entrees)
:after25

rem --- 26. ngrams=0 et ngrams=6 -^> exit 1 --------------------------------------
if "%NODE_OK%"=="1" goto :node26b
set NG0_OK=1
goto :after26b
:node26b
node -e "var cp=require('child_process');function chk(a){var r=cp.spawnSync(process.argv[1],a,{encoding:'utf8'});if(r.status===1&&/ngrams/.test(r.stderr)){return true;}console.error('[cas26] '+a.join(' ')+' exit='+r.status+' stdout='+JSON.stringify(r.stdout)+' stderr='+JSON.stringify(r.stderr));return false;}if(chk(['--ngrams=0','tests/fixtures/test_fr.txt'])&&chk(['--ngrams=6','tests/fixtures/test_fr.txt'])){process.exit(0);}process.exit(1);" "%FSTATS%"
if errorlevel 1 (set NG0_OK=0) else (set NG0_OK=1)
:after26b
if "%NG0_OK%"=="1" (set /a PASS+=1&echo PASS: --ngrams=0 / --ngrams=6 -^> exit 1 + message stderr) else (set /a FAIL+=1&echo FAIL: --ngrams=0 / --ngrams=6 -^> exit 1 + message stderr)

rem --- 27. stopwords=fr + ngrams=2 corpus_fr (golden) ---------------------------
"%FSTATS%" --json --ngrams=2 --top-ngrams=0 --stopwords=fr tests\fixtures\corpus_fr.txt > "%TMPD%\swfr.json" 2>nul
"%FSTATS%" --summary-json --stopwords=fr tests\fixtures\corpus_fr.txt > "%TMPD%\swno.json" 2>nul
if "%NODE_OK%"=="1" goto :node27
echo SKIP: swfr.json (node indisponible)
goto :after27
:node27
node -e "var fs=require('fs');var o=JSON.parse(fs.readFileSync(process.argv[1],'utf8'));var s=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));var n=o.ngrams;var has=function(a){return n.some(function(e){return e.words.length===2&&e.words[0]===a[0]&&e.words[1]===a[1];});};process.exit((o.statistics.words===20?0:1)+(n.length===14?0:1)+(has(['et','croissant,'])?1:0)+(has(['?','est'])?0:1)+(('ngrams' in s)?1:0));" "%TMPD%\swfr.json" "%TMPD%\swno.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --stopwords=fr --ngrams=2 corpus_fr.txt -^> 14 bigrammes, mots vides retires) else (set /a PASS+=1&echo PASS: --stopwords=fr --ngrams=2 corpus_fr.txt -^> 14 bigrammes, mots vides retires)
:after27

rem --- 28. histogram=line_length : classes roadmap + somme = lignes -------------
"%FSTATS%" --json --histogram=line_length tests\fixtures\test_fr.txt > "%TMPD%\hll.json" 2>nul
if "%NODE_OK%"=="1" goto :node28
echo SKIP: hll.json (node indisponible)
goto :after28
:node28
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var h=o.histogram;var sum=h.classes.reduce(function(a,c){return a+c.count;},0);var r=h.classes.map(function(c){return c.range;});process.exit((h.metric==='line_length'&&r[0]==='0-9'&&r[1]==='10-19'&&r[2]==='20-29'&&r[3]==='30-39'&&r[4]==='40+'&&sum===o.statistics.lines)?0:1);" < "%TMPD%\hll.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --histogram=line_length -^> classes 0-9..40+, somme = lignes) else (set /a PASS+=1&echo PASS: --histogram=line_length -^> classes 0-9..40+, somme = lignes)
:after28

rem --- 29. histogram=word_length : somme = mots ---------------------------------
"%FSTATS%" --json --histogram=word_length tests\fixtures\test_fr.txt > "%TMPD%\hwl.json" 2>nul
if "%NODE_OK%"=="1" goto :node29
echo SKIP: hwl.json (node indisponible)
goto :after29
:node29
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var h=o.histogram;var sum=h.classes.reduce(function(a,c){return a+c.count;},0);process.exit((h.metric==='word_length'&&sum===o.statistics.words)?0:1);" < "%TMPD%\hwl.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --histogram=word_length -^> somme des classes = mots) else (set /a PASS+=1&echo PASS: --histogram=word_length -^> somme des classes = mots)
:after29

rem --- 30. histogram=words_per_sentence : somme = phrases -----------------------
"%FSTATS%" --json --histogram=words_per_sentence tests\fixtures\test_fr.txt > "%TMPD%\hwps.json" 2>nul
if "%NODE_OK%"=="1" goto :node30
echo SKIP: hwps.json (node indisponible)
goto :after30
:node30
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var h=o.histogram;var sum=h.classes.reduce(function(a,c){return a+c.count;},0);process.exit((h.metric==='words_per_sentence'&&sum===o.statistics.sentences)?0:1);" < "%TMPD%\hwps.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --histogram=words_per_sentence -^> somme des classes = phrases) else (set /a PASS+=1&echo PASS: --histogram=words_per_sentence -^> somme des classes = phrases)
:after30

rem --- 31. char-classes : golden test_fr + somme = caracteres -------------------
"%FSTATS%" --json --char-classes tests\fixtures\test_fr.txt > "%TMPD%\cc.json" 2>nul
if "%NODE_OK%"=="1" goto :node31
echo SKIP: cc.json (node indisponible)
goto :after31
:node31
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var c=o.char_classes;var sum=c.letters+c.digits+c.whitespace+c.punctuation+c.control+c.other;process.exit((sum===o.statistics.characters&&c.letters===57&&c.digits===0&&c.whitespace===12&&c.punctuation===3&&c.control===0&&c.other===0)?0:1);" < "%TMPD%\cc.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --char-classes test_fr.txt -^> 57/0/12/3/0/0, somme = 72 caracteres) else (set /a PASS+=1&echo PASS: --char-classes test_fr.txt -^> 57/0/12/3/0/0, somme = 72 caracteres)
:after31

rem --- 32. aggregate + char-classes + histogram : totaux sommes -----------------
"%FSTATS%" tests\docs\**\*.md --json-mode=aggregate --char-classes --histogram=line_length > "%TMPD%\aggs.json" 2>nul
if "%NODE_OK%"=="1" goto :node32
echo SKIP: aggs.json (node indisponible)
goto :after32
:node32
node -e "var j=JSON.parse(require('fs').readFileSync(0,'utf8'));var t=j.totals;var cl={letters:0,digits:0,whitespace:0,punctuation:0,control:0,other:0};var hc={};for(var k=0;k<j.files.length;k++){var f=j.files[k];cl.letters+=f.char_classes.letters;cl.digits+=f.char_classes.digits;cl.whitespace+=f.char_classes.whitespace;cl.punctuation+=f.char_classes.punctuation;cl.control+=f.char_classes.control;cl.other+=f.char_classes.other;for(var m=0;m<f.histogram.classes.length;m++){hc[f.histogram.classes[m].range]=(hc[f.histogram.classes[m].range]||0)+f.histogram.classes[m].count;}}var okCC=cl.letters===t.char_classes.letters&&cl.digits===t.char_classes.digits&&cl.whitespace===t.char_classes.whitespace&&cl.punctuation===t.char_classes.punctuation&&cl.control===t.char_classes.control&&cl.other===t.char_classes.other;var okH=t.histogram.metric==='line_length'&&t.histogram.classes.every(function(c){return hc[c.range]===c.count;});var ngAbsent=('ngrams' in t)?0:1;process.exit((okCC&&okH&&ngAbsent)?0:1);" < "%TMPD%\aggs.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: aggregate --char-classes --histogram -^> totaux sommes classe par classe) else (set /a PASS+=1&echo PASS: aggregate --char-classes --histogram -^> totaux sommes classe par classe)
:after32

rem --- 33. Sortie pipee avec les nouvelles options : aucune sequence ANSI ------
"%FSTATS%" --ngrams=2 --histogram=line_length --char-classes tests\fixtures\test_fr.txt > "%TMPD%\console2.txt" 2>nul
if "%NODE_OK%"=="1" goto :node33
echo SKIP: controle ANSI C2-B (node indisponible)
goto :after33
:node33
node -e "var b=require('fs').readFileSync(0);process.exit(b.indexOf(27)<0?0:1);" < "%TMPD%\console2.txt"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: sortie pipee ngrams+histogram+char-classes : aucune sequence ANSI [ESC]) else (set /a PASS+=1&echo PASS: sortie pipee ngrams+histogram+char-classes : aucune sequence ANSI [ESC])
:after33

rem --- 34. --readability --summary-json (valeurs golden sur test_fr.txt) --------
"%FSTATS%" --readability --summary-json tests\fixtures\test_fr.txt > "%TMPD%\rd.json" 2>nul
if "%NODE_OK%"=="1" goto :node34
echo SKIP: rd.json (node indisponible)
goto :after34
:node34
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var ap=function(a,b){return Math.abs(a-b)<0.001;};process.exit((ap(o.avg_sentence_words,4.333333)&&ap(o.avg_word_chars,4.615385)&&ap(o.pct_long_words,23.076923)&&ap(o.readability_score,76.62395))?0:1);" < "%TMPD%\rd.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --readability --summary-json test_fr.txt -^> 4.333333/4.615385/23.076923/76.62395) else (set /a PASS+=1&echo PASS: --readability --summary-json test_fr.txt -^> 4.333333/4.615385/23.076923/76.62395)
:after34

rem --- 35. --readability --json : bloc readability avec les 4 cles --------------
"%FSTATS%" --readability --json tests\fixtures\test_fr.txt > "%TMPD%\rdj.json" 2>nul
if "%NODE_OK%"=="1" goto :node35
echo SKIP: rdj.json (node indisponible)
goto :after35
:node35
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));var r=o.readability;process.exit((r&&('avg_sentence_words' in r)&&('avg_word_chars' in r)&&('pct_long_words' in r)&&('score' in r))?0:1);" < "%TMPD%\rdj.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --readability --json -^> bloc readability avec les 4 cles) else (set /a PASS+=1&echo PASS: --readability --json -^> bloc readability avec les 4 cles)
:after35

rem --- 36. --readability --lexical-stats --summary-json : cles lexicales ET lisibilite
"%FSTATS%" --readability --lexical-stats --summary-json tests\fixtures\test_fr.txt > "%TMPD%\rdlx.json" 2>nul
if "%NODE_OK%"=="1" goto :node36
echo SKIP: rdlx.json (node indisponible)
goto :after36
:node36
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit((('unique_words' in o)&&('entropy_bits_per_word' in o)&&('avg_sentence_words' in o)&&('readability_score' in o))?0:1);" < "%TMPD%\rdlx.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --readability --lexical-stats --summary-json -^> cles lexicales ET lisibilite presentes) else (set /a PASS+=1&echo PASS: --readability --lexical-stats --summary-json -^> cles lexicales ET lisibilite presentes)
:after36

rem --- 37. --readability --csv : 4 lignes summary lisibilite --------------------
"%FSTATS%" --readability --csv tests\fixtures\test_fr.txt > "%TMPD%\rdc.csv" 2>nul
findstr /C:",summary,,avg_sentence_words,," "%TMPD%\rdc.csv" >nul && findstr /C:",summary,,avg_word_chars,," "%TMPD%\rdc.csv" >nul && findstr /C:",summary,,pct_long_words,," "%TMPD%\rdc.csv" >nul && findstr /C:",summary,,readability_score,," "%TMPD%\rdc.csv" >nul
if errorlevel 1 (set /a FAIL+=1&echo FAIL: --readability --csv -^> 4 lignes summary lisibilite) else (set /a PASS+=1&echo PASS: --readability --csv -^> 4 lignes summary lisibilite)

rem --- 38. Fichier vide : valeurs 0, score 0 (pas de division par zero) ---------
"%FSTATS%" --readability --summary-json tests\fixtures\empty.txt > "%TMPD%\rdempty.json" 2>nul
if "%NODE_OK%"=="1" goto :node38
echo SKIP: rdempty.json (node indisponible)
goto :after38
:node38
node -e "var o=JSON.parse(require('fs').readFileSync(0,'utf8'));process.exit((o.avg_sentence_words===0&&o.avg_word_chars===0&&o.pct_long_words===0&&o.readability_score===0)?0:1);" < "%TMPD%\rdempty.json"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: fichier vide --readability --summary-json -^> valeurs 0, score 0) else (set /a PASS+=1&echo PASS: fichier vide --readability --summary-json -^> valeurs 0, score 0)
:after38

rem --- 39. Sortie pipee --readability : aucune sequence ANSI --------------------
"%FSTATS%" --readability tests\fixtures\test_fr.txt > "%TMPD%\rdconsole.txt" 2>nul
if "%NODE_OK%"=="1" goto :node39
echo SKIP: controle ANSI C2-C (node indisponible)
goto :after39
:node39
node -e "var b=require('fs').readFileSync(0);process.exit(b.indexOf(27)<0?0:1);" < "%TMPD%\rdconsole.txt"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: sortie pipee --readability : aucune sequence ANSI [ESC]) else (set /a PASS+=1&echo PASS: sortie pipee --readability : aucune sequence ANSI [ESC])
:after39

rem --- 40. --check : exit 0 + JSON checks[0] ok [actual 3] -----------------------
if "%NODE_OK%"=="1" goto :node40
set C40_OK=1
goto :after40
:node40
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>5','--json','tests/fixtures/test_fr.txt'],{encoding:'utf8'});var o=JSON.parse(r.stdout);if(r.status===0&&o.checks.length===1&&o.checks[0].id==='lines'&&o.checks[0].metric==='lines'&&o.checks[0].actual===3&&o.checks[0].op==='>'&&o.checks[0].threshold===5&&o.checks[0].status==='ok'){process.exit(0);}console.error('[cas40] exit='+r.status+' checks='+JSON.stringify(o.checks));process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C40_OK=0) else (set C40_OK=1)
:after40
if "%C40_OK%"=="1" (set /a PASS+=1&echo PASS: --check --fail-if lines^>5 test_fr.txt -^> exit 0, checks[0] ok [entree complete]) else (set /a FAIL+=1&echo FAIL: --check --fail-if lines^>5 test_fr.txt -^> exit 0, checks[0] ok [entree complete])

rem --- 41. --check : exit 2 + JSON checks[0] fail [entree complete] --------------
if "%NODE_OK%"=="1" goto :node41
set C41_OK=1
goto :after41
:node41
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>2','--json','tests/fixtures/test_fr.txt'],{encoding:'utf8'});var o=JSON.parse(r.stdout);if(r.status===2&&o.checks.length===1&&o.checks[0].id==='lines'&&o.checks[0].metric==='lines'&&o.checks[0].actual===3&&o.checks[0].op==='>'&&o.checks[0].threshold===2&&o.checks[0].status==='fail'){process.exit(0);}console.error('[cas41] exit='+r.status+' checks='+JSON.stringify(o.checks));process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C41_OK=0) else (set C41_OK=1)
:after41
if "%C41_OK%"=="1" (set /a PASS+=1&echo PASS: --check --fail-if lines^>2 test_fr.txt -^> exit 2, checks[0] fail) else (set /a FAIL+=1&echo FAIL: --check --fail-if lines^>2 test_fr.txt -^> exit 2, checks[0] fail)

rem --- 42. --check --warn-if : exit 3 + status warn ------------------------------
if "%NODE_OK%"=="1" goto :node42
set C42_OK=1
goto :after42
:node42
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--check','--warn-if','lines>2','--json','tests/fixtures/test_fr.txt'],{encoding:'utf8'});var o=JSON.parse(r.stdout);if(r.status===3&&o.checks.length===1&&o.checks[0].status==='warn'){process.exit(0);}console.error('[cas42] exit='+r.status+' checks='+JSON.stringify(o.checks));process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C42_OK=0) else (set C42_OK=1)
:after42
if "%C42_OK%"=="1" (set /a PASS+=1&echo PASS: --check --warn-if lines^>2 -^> exit 3, status warn) else (set /a FAIL+=1&echo FAIL: --check --warn-if lines^>2 -^> exit 3, status warn)

rem --- 43. --check --fail-if max_line_length^>25 (max 30) : exit 2 ---------------
if "%NODE_OK%"=="1" goto :node43
set C43_OK=1
goto :after43
:node43
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--check','--fail-if','max_line_length>25','tests/fixtures/test_fr.txt'],{encoding:'utf8'});if(r.status===2){process.exit(0);}console.error('[cas43] exit='+r.status);process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C43_OK=0) else (set C43_OK=1)
:after43
if "%C43_OK%"=="1" (set /a PASS+=1&echo PASS: --check --fail-if max_line_length^>25 test_fr.txt -^> exit 2 [max 30]) else (set /a FAIL+=1&echo FAIL: --check --fail-if max_line_length^>25 test_fr.txt -^> exit 2 [max 30])

rem --- 44. Mode check implicite (sans --check) : exit 2 --------------------------
if "%NODE_OK%"=="1" goto :node44
set C44_OK=1
goto :after44
:node44
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--fail-if','lines>2','tests/fixtures/test_fr.txt'],{encoding:'utf8'});if(r.status===2){process.exit(0);}console.error('[cas44] exit='+r.status);process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C44_OK=0) else (set C44_OK=1)
:after44
if "%C44_OK%"=="1" (set /a PASS+=1&echo PASS: mode implicite : --fail-if lines^>2 sans --check -^> exit 2) else (set /a FAIL+=1&echo FAIL: mode implicite : --fail-if lines^>2 sans --check -^> exit 2)

rem --- 45. Syntaxe invalide --fail-if : exit 1 + stderr --------------------------
if "%NODE_OK%"=="1" goto :node45
set C45_OK=1
goto :after45
:node45
node -e "var cp=require('child_process');function chk(a){var r=cp.spawnSync(process.argv[1],a,{encoding:'utf8'});if(r.status===1&&r.stderr.length>0&&/fail-if/.test(r.stderr)){return true;}console.error('[cas45] '+a.join(' ')+' exit='+r.status+' stderr='+JSON.stringify(r.stderr));return false;}if(chk(['--fail-if','lines','tests/fixtures/test_fr.txt'])&&chk(['--fail-if','nope>1','tests/fixtures/test_fr.txt'])){process.exit(0);}process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C45_OK=0) else (set C45_OK=1)
:after45
if "%C45_OK%"=="1" (set /a PASS+=1&echo PASS: --fail-if sans op / metrique inconnue -^> exit 1 + stderr) else (set /a FAIL+=1&echo FAIL: --fail-if sans op / metrique inconnue -^> exit 1 + stderr)

rem --- 46. Fichier vide : lines^>=0 -^> exit 2 ; lines^>0 -^> exit 0 --------------
if "%NODE_OK%"=="1" goto :node46
set C46_OK=1
goto :after46
:node46
node -e "var cp=require('child_process');var a=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>=0','tests/fixtures/empty.txt'],{encoding:'utf8'});var b=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>0','tests/fixtures/empty.txt'],{encoding:'utf8'});if(a.status===2&&b.status===0){process.exit(0);}console.error('[cas46] lines>=0 exit='+a.status+' lines>0 exit='+b.status);process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C46_OK=0) else (set C46_OK=1)
:after46
if "%C46_OK%"=="1" (set /a PASS+=1&echo PASS: empty.txt : lines^>=0 -^> exit 2, lines^>0 -^> exit 0) else (set /a FAIL+=1&echo FAIL: empty.txt : lines^>=0 -^> exit 2, lines^>0 -^> exit 0)

rem --- 47. Multi-fichiers : pire statut cumule (fail ^> warn ^> ok) --------------
if "%NODE_OK%"=="1" goto :node47
set C47_OK=1
goto :after47
:node47
node -e "var cp=require('child_process');var a=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>3','tests/fixtures/test_fr.txt','tests/fixtures/bom.txt'],{encoding:'utf8'});var b=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>1','tests/fixtures/test_fr.txt','tests/fixtures/bom.txt'],{encoding:'utf8'});if(a.status===0&&b.status===2){process.exit(0);}console.error('[cas47] lines>3 exit='+a.status+' lines>1 exit='+b.status);process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C47_OK=0) else (set C47_OK=1)
:after47
if "%C47_OK%"=="1" (set /a PASS+=1&echo PASS: multi-fichiers : lines^>3 -^> exit 0, lines^>1 -^> exit 2 [pire statut]) else (set /a FAIL+=1&echo FAIL: multi-fichiers : lines^>3 -^> exit 0, lines^>1 -^> exit 2 [pire statut])

rem --- 48. Baseline --compare + --fail-on-delta ----------------------------------
"%FSTATS%" --summary-json tests/fixtures/test_fr.txt > "%TMPD%\base.json" 2>nul
if "%NODE_OK%"=="1" goto :node48b
set C48_OK=1
goto :after48
:node48b
node -e "var fs=require('fs');var s=fs.readFileSync(process.argv[1],'utf8');fs.writeFileSync(process.argv[2],s.replace('\"lines\": 3','\"lines\": 1'));" "%TMPD%\base.json" "%TMPD%\base2.json"
:node48
node -e "var cp=require('child_process');function run(a){var r=cp.spawnSync(process.argv[1],a,{encoding:'utf8'});return {st:r.status,out:r.stdout};}var a=run(['--compare',process.argv[2],'--fail-on-delta','lines>10','tests/fixtures/test_fr.txt']);var b=run(['--compare',process.argv[3],'--fail-on-delta','lines>10','tests/fixtures/test_fr.txt']);if(a.st===0&&b.st===2&&b.out.indexOf('FAIL (delta 200%%)')>=0){process.exit(0);}console.error('[cas48] base exit='+a.st+' modif exit='+b.st+' delta='+b.out.indexOf('FAIL (delta 200%%)'));process.exit(1);" "%FSTATS%" "%TMPD%\base.json" "%TMPD%\base2.json"
if errorlevel 1 (set C48_OK=0) else (set C48_OK=1)
:after48
if "%C48_OK%"=="1" (set /a PASS+=1&echo PASS: --compare --fail-on-delta lines^>10 -^> exit 0 ; baseline lines:1 -^> exit 2 [delta 200%%]) else (set /a FAIL+=1&echo FAIL: --compare --fail-on-delta lines^>10 -^> exit 0 ; baseline lines:1 -^> exit 2 [delta 200%%])

rem --- 49. --fail-on-delta sans --compare : exit 1 -------------------------------
if "%NODE_OK%"=="1" goto :node49
set C49_OK=1
goto :after49
:node49
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--fail-on-delta','lines>10','tests/fixtures/test_fr.txt'],{encoding:'utf8'});if(r.status===1&&/compare/.test(r.stderr)){process.exit(0);}console.error('[cas49] exit='+r.status+' stderr='+JSON.stringify(r.stderr));process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C49_OK=0) else (set C49_OK=1)
:after49
if "%C49_OK%"=="1" (set /a PASS+=1&echo PASS: --fail-on-delta sans --compare -^> exit 1 + stderr) else (set /a FAIL+=1&echo FAIL: --fail-on-delta sans --compare -^> exit 1 + stderr)

rem --- 50. Fichier manquant avec --check : exit 1 (fatal prime) ------------------
if "%NODE_OK%"=="1" goto :node50
set C50_OK=1
goto :after50
:node50
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>1','absent.txt'],{encoding:'utf8'});if(r.status===1){process.exit(0);}console.error('[cas50] exit='+r.status);process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C50_OK=0) else (set C50_OK=1)
:after50
if "%C50_OK%"=="1" (set /a PASS+=1&echo PASS: --check --fail-if lines^>1 absent.txt -^> exit 1 [fatal prime]) else (set /a FAIL+=1&echo FAIL: --check --fail-if lines^>1 absent.txt -^> exit 1 [fatal prime])

rem --- 51. Mode analyse sans --check : exit 0 inchange ---------------------------
if "%NODE_OK%"=="1" goto :node51
set C51_OK=1
goto :after51
:node51
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['tests/fixtures/test_fr.txt'],{encoding:'utf8'});if(r.status===0&&r.stdout.length>0&&r.stdout.indexOf('\x1b')<0){process.exit(0);}console.error('[cas51] exit='+r.status);process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C51_OK=0) else (set C51_OK=1)
:after51
if "%C51_OK%"=="1" (set /a PASS+=1&echo PASS: mode analyse test_fr.txt -^> exit 0, sortie console sans ANSI) else (set /a FAIL+=1&echo FAIL: mode analyse test_fr.txt -^> exit 0, sortie console sans ANSI)

rem --- 52. Delta infini (base 0 -^> actual ^> 0) : exit 2 ; 0 -^> 0 : exit 0 ------
"%FSTATS%" --summary-json tests/fixtures/test_fr.txt > "%TMPD%\baseinf.json" 2>nul
"%FSTATS%" --summary-json tests/fixtures/empty.txt > "%TMPD%\baseemp.json" 2>nul
if "%NODE_OK%"=="1" goto :node52b
set C52_OK=1
goto :after52
:node52b
node -e "var fs=require('fs');var s=fs.readFileSync(process.argv[1],'utf8');fs.writeFileSync(process.argv[2],s.replace('\"words\": 13','\"words\": 0'));" "%TMPD%\baseinf.json" "%TMPD%\baseinf2.json"
:node52
node -e "var cp=require('child_process');var a=cp.spawnSync(process.argv[1],['--compare',process.argv[2],'--fail-on-delta','words>0','tests/fixtures/test_fr.txt'],{encoding:'utf8'});var b=cp.spawnSync(process.argv[1],['--compare',process.argv[3],'--fail-on-delta','words>0','tests/fixtures/empty.txt'],{encoding:'utf8'});if(a.status===2&&a.stdout.indexOf('delta inf%%')>=0&&b.status===0){process.exit(0);}console.error('[cas52] inf exit='+a.status+' inf='+a.stdout.indexOf('delta inf%%')+' zero exit='+b.status);process.exit(1);" "%FSTATS%" "%TMPD%\baseinf2.json" "%TMPD%\baseemp.json"
if errorlevel 1 (set C52_OK=0) else (set C52_OK=1)
:after52
if "%C52_OK%"=="1" (set /a PASS+=1&echo PASS: delta infini : base 0 -^> 13 exit 2 [delta inf%%] ; 0 -^> 0 exit 0) else (set /a FAIL+=1&echo FAIL: delta infini : base 0 -^> 13 exit 2 [delta inf%%] ; 0 -^> 0 exit 0)

rem --- 53. Sortie pipee --check : aucune sequence ANSI ---------------------------
"%FSTATS%" --check --fail-if lines>2 tests\fixtures\test_fr.txt > "%TMPD%\chkconsole.txt" 2>nul
if "%NODE_OK%"=="1" goto :node53
echo SKIP: controle ANSI checks (node indisponible)
goto :after53
:node53
node -e "var b=require('fs').readFileSync(0);process.exit(b.indexOf(27)<0?0:1);" < "%TMPD%\chkconsole.txt"
if errorlevel 1 (set /a FAIL+=1&echo FAIL: sortie pipee --check : aucune sequence ANSI [ESC]) else (set /a PASS+=1&echo PASS: sortie pipee --check : aucune sequence ANSI [ESC])
:after53

rem --- 54. --summary-json + checks : pas de section, exit 2 applique -------------
if "%NODE_OK%"=="1" goto :node54
set C54_OK=1
goto :after54
:node54
node -e "var cp=require('child_process');var r=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>2','--summary-json','tests/fixtures/test_fr.txt'],{encoding:'utf8'});var o=JSON.parse(r.stdout);if(r.status===2&&!('checks' in o)){process.exit(0);}console.error('[cas54] exit='+r.status+' checks in o: '+('checks' in o));process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C54_OK=0) else (set C54_OK=1)
:after54
if "%C54_OK%"=="1" (set /a PASS+=1&echo PASS: --summary-json + checks -^> pas de section checks, exit 2 applique) else (set /a FAIL+=1&echo FAIL: --summary-json + checks -^> pas de section checks, exit 2 applique)

rem --- 55. Grammaire : espaces autour de l'operateur + seuil decimal ------------
if "%NODE_OK%"=="1" goto :node55
set C55_OK=1
goto :after55
:node55
node -e "var cp=require('child_process');var a=cp.spawnSync(process.argv[1],['--check','--fail-if','lines > 2.5','tests/fixtures/test_fr.txt'],{encoding:'utf8'});var b=cp.spawnSync(process.argv[1],['--check','--fail-if','lines','>','2','tests/fixtures/test_fr.txt'],{encoding:'utf8'});if(a.status===2&&b.status===2){process.exit(0);}console.error('[cas55] espace exit='+a.status+' 3args exit='+b.status);process.exit(1);" "%FSTATS%"
if errorlevel 1 (set C55_OK=0) else (set C55_OK=1)
:after55
if "%C55_OK%"=="1" (set /a PASS+=1&echo PASS: '--fail-if lines ^> 2.5' et 3 arguments separes -^> exit 2) else (set /a FAIL+=1&echo FAIL: '--fail-if lines ^> 2.5' et 3 arguments separes -^> exit 2)

rem --- 56. Ids de repetition + aggregate (checks par fichier, pas dans totals) --
"%FSTATS%" --summary-json tests/fixtures/test_fr.txt > "%TMPD%\base56.json" 2>nul
if "%NODE_OK%"=="1" goto :node56b
set C56_OK=1
goto :after56
:node56b
node -e "var fs=require('fs');var s=fs.readFileSync(process.argv[1],'utf8');fs.writeFileSync(process.argv[2],s.replace('\"lines\": 3','\"lines\": 1'));" "%TMPD%\base56.json" "%TMPD%\base56b.json"
:node56
node -e "var cp=require('child_process');var r1=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>1','--fail-if','lines>100','--json','tests/fixtures/test_fr.txt'],{encoding:'utf8'});var o1=JSON.parse(r1.stdout);var ids1=o1.checks.map(function(c){return c.id;});var st1=o1.checks.map(function(c){return c.status;});var r2=cp.spawnSync(process.argv[1],['--compare',process.argv[3],'--fail-on-delta','lines>10','--fail-on-delta','lines>100','--json','tests/fixtures/test_fr.txt'],{encoding:'utf8'});var o2=JSON.parse(r2.stdout);var ids2=o2.checks.map(function(c){return c.id;});var r3=cp.spawnSync(process.argv[1],['--check','--fail-if','lines>2','--json-mode=aggregate','tests/fixtures/test_fr.txt','tests/fixtures/bom.txt'],{encoding:'utf8'});var o3=JSON.parse(r3.stdout);var ok1=r1.status===2&&ids1.join(',')==='lines,lines#2'&&st1.join(',')==='fail,ok';var ok2=r2.status===2&&ids2.join(',')==='delta:lines,delta:lines#2';var ok3=r3.status===2&&o3.files[0].checks&&o3.files[1].checks&&!('checks' in o3.totals);if(ok1&&ok2&&ok3){process.exit(0);}console.error('[cas56] ids1='+ids1+' st1='+st1+' r1='+r1.status+' ids2='+ids2+' r2='+r2.status+' r3='+r3.status);process.exit(1);" "%FSTATS%" "%TMPD%\base56.json" "%TMPD%\base56b.json"
if errorlevel 1 (set C56_OK=0) else (set C56_OK=1)
:after56
if "%C56_OK%"=="1" (set /a PASS+=1&echo PASS: ids lines/lines#2 et delta:lines/delta:lines#2, aggregate sans checks dans totals) else (set /a FAIL+=1&echo FAIL: ids lines/lines#2 et delta:lines/delta:lines#2, aggregate sans checks dans totals)

echo.
echo RESULTAT : %PASS% reussi, %FAIL% echec(s)
rd /s /q "%TMPD%" >nul 2>nul
if "%FAIL%"=="0" exit /b 0
exit /b 1
