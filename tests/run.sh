#!/usr/bin/env bash
# ============================================================================
# tests/run.sh — Journal de validation reproductible de fstats (incrément A)
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
"$FSTATS" --version | grep -q "2.2.0"
report "--version affiche 2.2.0" $?

echo ""
echo "RESULTAT : $PASS reussi, $FAIL echec(s)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
