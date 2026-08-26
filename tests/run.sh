#!/usr/bin/env bash
# ============================================================================
# tests/run.sh — Journal de validation reproductible de fstats
# (incréments A + C2-A "Lexique", v2.3.0)
# Usage : bash tests/run.sh   (depuis n'importe où)
# Prérequis : fpc et node sur le PATH.
# Compile fstats, exécute les cas d'acceptation, vérifie les exit codes et
# valide le JSON avec node. Sortie : une ligne PASS/FAIL par cas, puis un
# bilan. Exit 0 si tout passe, 1 sinon.
# ============================================================================
set -u

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

PASS=0
FAIL=0
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

report() { # <nom> <ok 0/1>
  if [ "$2" -eq 0 ]; then
    echo "PASS: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1"
    FAIL=$((FAIL + 1))
  fi
}

# --- 1. Compilation ---------------------------------------------------------
# Sans -FE, FPC place l'executable dans src/ : fstats.exe (Windows) ou fstats (POSIX)
fpc -O2 -Mobjfpc src/fstats.pas > "$TMPDIR/compile.log" 2>&1
report "compilation : fpc -O2 -Mobjfpc src/fstats.pas (exit 0)" $?
grep -oE "[0-9]+ lines compiled" "$TMPDIR/compile.log" | head -1

# Nom du binaire selon la plateforme
if [ -f "$ROOT/src/fstats.exe" ]; then
  FSTATS="$ROOT/src/fstats.exe"
else
  FSTATS="$ROOT/src/fstats"
fi

# --- 2. Compteurs de référence (tests/fixtures/test_fr.txt) -----------------
"$FSTATS" --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/test_fr.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
console.log("  tests/fixtures/test_fr.txt -> lines=" + o.lines + " words=" + o.words +
  " chars=" + o.characters + " sentences=" + o.sentences +
  " avg=" + o.avg_words_per_sentence + " min/max/avg=" +
  o.line_min + "/" + o.line_max + "/" + o.line_avg);
process.exit((o.lines === 3 && o.words === 13 && o.characters === 72 &&
  o.sentences === 3 && o.avg_words_per_sentence === 4 &&
  o.line_min === 16 && o.line_max === 30 && o.line_avg === 23) ? 0 : 1);
' "$TMPDIR/test_fr.json"
report "tests/fixtures/test_fr.txt : 3/13/72/3, moy 4, min/max/moy 16/30/23 (inchangés)" $?

# --- 3. stdin JSON ----------------------------------------------------------
echo "un deux trois." | "$FSTATS" - --json > "$TMPDIR/stdin.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit(o.statistics.words === 3 ? 0 : 1);' "$TMPDIR/stdin.json"
report "stdin : echo \"un deux trois.\" | fstats - --json (words=3, objet JSON valide)" $?

# --- 4. stdin mélangé avec des fichiers = erreur fatale ---------------------
"$FSTATS" - tests/fixtures/test_fr.txt > "$TMPDIR/mix.out" 2> "$TMPDIR/mix.err"
if [ $? -eq 1 ] && grep -q "standard" "$TMPDIR/mix.err"; then OK=0; else OK=1; fi
report "stdin + fichier : fstats - tests/fixtures/test_fr.txt -> exit 1 + message stderr" $OK

# --- 5. NDJSON multi-fichiers ------------------------------------------------
"$FSTATS" tests/fixtures/bom.txt tests/fixtures/crlf.txt --json > "$TMPDIR/nd.json" 2>/dev/null
node -e '
var fs = require("fs");
var lines = fs.readFileSync(process.argv[1], "utf8").trim().split(/\r?\n/);
if (lines.length !== 2) process.exit(1);
var a = JSON.parse(lines[0]), b = JSON.parse(lines[1]);
process.exit((a.quality.bom === true && b.quality.crlf === 2) ? 0 : 1);
' "$TMPDIR/nd.json"
report "NDJSON : 2 fichiers -> 2 lignes, chacune parseable (bom=true, crlf=2)" $?

# --- 6. Aggregate (glob **) --------------------------------------------------
"$FSTATS" 'tests/docs/**/*.md' --json-mode=aggregate > "$TMPDIR/agg.json" 2>/dev/null
node -e '
var j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var t = j.totals, fl = 0, wo = 0, ch = 0, se = 0;
for (var k = 0; k < j.files.length; k++) {
  fl += j.files[k].statistics.lines; wo += j.files[k].statistics.words;
  ch += j.files[k].statistics.characters; se += j.files[k].statistics.sentences;
}
process.exit((j.files.length === 3 && fl === t.lines && wo === t.words &&
  ch === t.characters && se === t.sentences) ? 0 : 1);
' "$TMPDIR/agg.json"
report "aggregate : tests/docs/**/*.md -> 3 fichiers, totaux cohérents" $?

# --- 7. summary-json (objet plat) --------------------------------------------
"$FSTATS" --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/sum.json" 2>/dev/null
node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));' "$TMPDIR/sum.json"
report "--summary-json tests/fixtures/test_fr.txt -> objet plat JSON valide" $?

# --- 8. Compteur qualité invalid_utf8 ----------------------------------------
"$FSTATS" tests/fixtures/invalid-utf8.bin --summary-json > "$TMPDIR/inv.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit(o.invalid_utf8 > 0 ? 0 : 1);' "$TMPDIR/inv.json"
report "fixture invalid-utf8.bin : invalid_utf8 > 0 dans le JSON" $?

# --- 9. Fichier absent -> exit 1 ---------------------------------------------
"$FSTATS" absent.txt > "$TMPDIR/abs.out" 2> "$TMPDIR/abs.err"
if [ $? -eq 1 ] && [ ! -s "$TMPDIR/abs.out" ]; then OK=0; else OK=1; fi
report "fstats absent.txt -> exit 1, stdout vide, message stderr" $OK

# --- 10. Glob sans correspondance -> exit 1 ----------------------------------
"$FSTATS" 'tests/**/*.nonexistent' > "$TMPDIR/glob.out" 2> "$TMPDIR/glob.err"
if [ $? -eq 1 ]; then OK=0; else OK=1; fi
report "glob sans correspondance -> exit 1 (gate CI jamais silencieusement vide)" $OK

# --- 11. Sortie pipee sans sequence ANSI --------------------------------------
"$FSTATS" tests/fixtures/test_fr.txt > "$TMPDIR/console.txt" 2>/dev/null
if grep -q $'\x1b' "$TMPDIR/console.txt"; then OK=1; else OK=0; fi
report "sortie console pipee : aucune sequence ANSI (ESC)" $OK

# --- 12. Version ---------------------------------------------------------------
"$FSTATS" --version | grep -q "2.3.0"
report "--version affiche 2.3.0" $?

# --- 13. word-mode=ascii (corpus EN, ponctuation) ---------------------------
"$FSTATS" --summary-json --word-mode=ascii tests/fixtures/corpus_en.txt > "$TMPDIR/ascii.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit(o.words === 11 ? 0 : 1);' "$TMPDIR/ascii.json"
report "--word-mode=ascii corpus_en.txt -> words=11 [golden]" $?

# --- 14. casefold=unicode (corpus FR accentué) -------------------------------
"$FSTATS" --summary-json --lexical-stats --casefold=unicode tests/fixtures/corpus_fr.txt > "$TMPDIR/cfuni.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit((o.unique_words === 16 && o.words === 20) ? 0 : 1);' "$TMPDIR/cfuni.json"
report "--casefold=unicode corpus_fr.txt -> unique_words=16, words=20" $?

# --- 15. casefold=none (casse conservée) -------------------------------------
"$FSTATS" --summary-json --lexical-stats --casefold=none tests/fixtures/corpus_fr.txt > "$TMPDIR/cfnone.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit((o.unique_words === 17 && o.words === 20) ? 0 : 1);' "$TMPDIR/cfnone.json"
report "--casefold=none corpus_fr.txt -> unique_words=17 (casse conservée)" $?

# --- 16. --lexical-stats (JSON) ----------------------------------------------
"$FSTATS" --json --lexical-stats tests/fixtures/test_fr.txt > "$TMPDIR/lex.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var l = o.lexical;
var ok = l.unique_words === 12 && l.hapax === 11 && l.average_word_length > 0 &&
  Math.abs(l.type_token_ratio - l.unique_words / o.statistics.words) < 1e-4 &&
  l.entropy_bits_per_word >= 0 &&
  l.entropy_bits_per_word <= Math.log2(l.unique_words) + 1e-9;
process.exit(ok ? 0 : 1);
' "$TMPDIR/lex.json"
report "--lexical-stats : champs présents, TTR=types/tokens, entropie bornée" $?

# --- 17. --top-words=5 / --top-chars=3 ---------------------------------------
"$FSTATS" --json --top-words=5 --top-chars=3 tests/fixtures/test_fr.txt > "$TMPDIR/top.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit((o.top_words.length === 5 && o.top_characters.length === 3) ? 0 : 1);' "$TMPDIR/top.json"
report "--top-words=5 --top-chars=3 -> exactement 5 et 3 entrées" $?

# --- 18. --top-words=0 = --all (section mots) ---------------------------------
"$FSTATS" --json --top-words=0 tests/fixtures/test_fr.txt > "$TMPDIR/top0.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit(o.top_words.length === 12 ? 0 : 1);' "$TMPDIR/top0.json"
report "--top-words=0 -> tous les mots (12 pour test_fr.txt)" $?

# --- 19. --max-unique (borne mémoire) ----------------------------------------
"$FSTATS" --summary-json --lexical-stats --max-unique=5 tests/fixtures/test_fr.txt > "$TMPDIR/mu.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit((o.unique_words === 5 && o.words === 13) ? 0 : 1);' "$TMPDIR/mu.json"
report "--max-unique=5 -> unique_words plafonné à 5, words=13 inchangé" $?

# --- 20. CSV v2 (en-tête + ligne summary + csv=words) -------------------------
"$FSTATS" --csv tests/fixtures/test_fr.txt > "$TMPDIR/csv2.csv" 2>/dev/null
"$FSTATS" --csv=words tests/fixtures/test_fr.txt > "$TMPDIR/csv2w.csv" 2>/dev/null
node -e '
var fs = require("fs");
var s = fs.readFileSync(process.argv[1], "utf8");
var w = fs.readFileSync(process.argv[2], "utf8");
var L = s.trim().split(/\r?\n/);
var H = "file,type,rank,value,code_point,count,length";
var okS = L.slice(1).some(function (r) {
  var c = r.split(",");
  return c[1] === "summary" && c[3] === "lines" && c[5] === "3" &&
    c[0].indexOf("test_fr.txt") >= 0;
});
var W = w.trim().split(/\r?\n/);
process.exit((L[0] === H && okS && W[0] === H && W.length === 11) ? 0 : 1);
' "$TMPDIR/csv2.csv" "$TMPDIR/csv2w.csv"
report "CSV v2 : en-tête exact, ligne summary avec colonne file, csv=words 10 lignes" $?

# --- 21. word-mode=unicode (corpus FR) ---------------------------------------
"$FSTATS" --summary-json --word-mode=unicode tests/fixtures/corpus_fr.txt > "$TMPDIR/uni.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit(o.words === 19 ? 0 : 1);' "$TMPDIR/uni.json"
report "--word-mode=unicode corpus_fr.txt -> words=19 [golden]" $?

# --- 22. Option lexicale invalide -> exit 1 -----------------------------------
"$FSTATS" --word-mode=bogus tests/fixtures/test_fr.txt > "$TMPDIR/bad.out" 2> "$TMPDIR/bad.err"
if [ $? -eq 1 ] && grep -q "word-mode" "$TMPDIR/bad.err"; then OK=0; else OK=1; fi
report "--word-mode=bogus -> exit 1 + message stderr" $OK

echo ""
echo "RESULTAT : $PASS reussi, $FAIL echec(s)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
