#!/usr/bin/env bash
# ============================================================================
# tests/run.sh — Journal de validation reproductible de fstats
# (incréments A + C2-A "Lexique" + C2-B "Structure" + C2-C "Lisibilité"
# + Cible 1 B "Checks" + Cible 1 C "Baseline"
# + v2.6.1 (3.14 ne cloture pas une phrase) + v2.7.0 (--sentence-mode basic|smart))
# Usage : bash tests/run.sh   (depuis n'importe où)
# Prérequis : fpc et node sur le PATH.
# Compile fstats, exécute les cas d'acceptation, vérifie les exit codes et
# valide le JSON avec node. Sortie : une ligne PASS/FAIL par cas, puis un
# bilan. Exit 0 si tout passe, 1 sinon.
# ============================================================================
set -u
# GitHub Actions lance les etapes bash avec `-e -o pipefail`, ce qui tuerait
# ce script au premier cas dont l'exit code non nul est VOULU (fichier absent,
# glob vide, stdin+ficher, option invalide). La gestion d'erreur est interne :
# compteur FAIL + exit 0/1 en fin de script. On desactive donc -e.
set +e

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
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
  echo "--- compile.log (echec) ---"
  cat "$TMPDIR/compile.log"
  echo "--- fin compile.log ---"
fi
report "compilation : fpc -O2 -Mobjfpc src/fstats.pas (exit $STATUS)" "$STATUS"
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
if (lines.length !== 2) { console.error("nd.json: " + lines.length + " ligne(s), attendu 2"); process.exit(1); }
var a = JSON.parse(lines[0]), b = JSON.parse(lines[1]);
console.error("nd.json: bom=" + a.quality.bom + " crlf=" + b.quality.crlf + " (attendu true/2)");
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
"$FSTATS" --version | grep -q "2.7.0"
report "--version affiche 2.7.0" $?

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

# --- 23. ngrams=2 corpus_en (golden, fenêtres par ligne) ----------------------
"$FSTATS" --json --ngrams=2 --word-mode=ascii tests/fixtures/corpus_en.txt > "$TMPDIR/ng2.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var n = o.ngrams;
var has = function (a) {
  return n.some(function (e) {
    return e.words.length === 2 && e.words[0] === a[0] && e.words[1] === a[1];
  });
};
var ok = n.length === 9 && n.every(function (e) { return e.count === 1; }) &&
  has(["hello", "world"]) && !has(["test", "one"]);
process.exit(ok ? 0 : 1);
' "$TMPDIR/ng2.json"
report "--ngrams=2 --word-mode=ascii corpus_en.txt -> 9 bigrammes, pas de [test one]" $?

# --- 24. ngram_lines.txt : pas de traversée des sauts de ligne -----------------
"$FSTATS" --json --ngrams=2 tests/fixtures/ngram_lines.txt > "$TMPDIR/ngl.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var n = o.ngrams;
var has = function (a) {
  return n.some(function (e) {
    return e.words.length === 2 && e.words[0] === a[0] && e.words[1] === a[1];
  });
};
process.exit((n.length === 2 && has(["alpha", "beta"]) && has(["gamma", "delta"]) &&
  !has(["beta", "gamma"])) ? 0 : 1);
' "$TMPDIR/ngl.json"
report "ngram_lines.txt -> 2 bigrammes, pas de [beta gamma]" $?

# --- 25. ngrams=3 top-ngrams=2 -> exactement 2 entrées ------------------------
"$FSTATS" --json --ngrams=3 --top-ngrams=2 tests/fixtures/test_fr.txt > "$TMPDIR/ng3.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit(o.ngrams.length === 2 ? 0 : 1);' "$TMPDIR/ng3.json"
report "--ngrams=3 --top-ngrams=2 -> exactement 2 entrées" $?

# --- 26. ngrams=0 et ngrams=6 -> exit 1 ----------------------------------------
"$FSTATS" --ngrams=0 tests/fixtures/test_fr.txt > "$TMPDIR/ng0.out" 2> "$TMPDIR/ng0.err"
if [ $? -eq 1 ] && grep -q "ngrams" "$TMPDIR/ng0.err"; then OK=0; else OK=1; fi
"$FSTATS" --ngrams=6 tests/fixtures/test_fr.txt > "$TMPDIR/ng6.out" 2> "$TMPDIR/ng6.err"
if [ $? -eq 1 ] && grep -q "ngrams" "$TMPDIR/ng6.err"; then OK=0; else OK=1; fi
report "--ngrams=0 / --ngrams=6 -> exit 1 + message stderr" $OK

# --- 27. stopwords=fr + ngrams=2 corpus_fr (golden) ----------------------------
"$FSTATS" --json --ngrams=2 --top-ngrams=0 --stopwords=fr tests/fixtures/corpus_fr.txt > "$TMPDIR/swfr.json" 2>/dev/null
"$FSTATS" --summary-json --stopwords=fr tests/fixtures/corpus_fr.txt > "$TMPDIR/swno.json" 2>/dev/null
node -e '
var fs = require("fs");
var o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
var s = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
var n = o.ngrams;
var has = function (a) {
  return n.some(function (e) {
    return e.words.length === 2 && e.words[0] === a[0] && e.words[1] === a[1];
  });
};
var ok = o.statistics.words === 20 && n.length === 14 &&
  !has(["et", "croissant,"]) && has(["?", "est"]) && !("ngrams" in s);
process.exit(ok ? 0 : 1);
' "$TMPDIR/swfr.json" "$TMPDIR/swno.json"
report "--stopwords=fr --ngrams=2 corpus_fr.txt -> 14 bigrammes, mots vides retirés" $?

# --- 28. histogram=line_length : classes roadmap + somme = lignes --------------
"$FSTATS" --json --histogram=line_length tests/fixtures/test_fr.txt > "$TMPDIR/hll.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var h = o.histogram;
var sum = h.classes.reduce(function (a, c) { return a + c.count; }, 0);
var r = h.classes.map(function (c) { return c.range; });
var ok = h.metric === "line_length" && r[0] === "0-9" && r[1] === "10-19" &&
  r[2] === "20-29" && r[3] === "30-39" && r[4] === "40+" && sum === o.statistics.lines;
process.exit(ok ? 0 : 1);
' "$TMPDIR/hll.json"
report "--histogram=line_length -> classes 0-9..40+, somme = lignes" $?

# --- 29. histogram=word_length : somme = mots ----------------------------------
"$FSTATS" --json --histogram=word_length tests/fixtures/test_fr.txt > "$TMPDIR/hwl.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var h = o.histogram;
var sum = h.classes.reduce(function (a, c) { return a + c.count; }, 0);
process.exit((h.metric === "word_length" && sum === o.statistics.words) ? 0 : 1);
' "$TMPDIR/hwl.json"
report "--histogram=word_length -> somme des classes = mots" $?

# --- 30. histogram=words_per_sentence : somme = phrases ------------------------
"$FSTATS" --json --histogram=words_per_sentence tests/fixtures/test_fr.txt > "$TMPDIR/hwps.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var h = o.histogram;
var sum = h.classes.reduce(function (a, c) { return a + c.count; }, 0);
process.exit((h.metric === "words_per_sentence" && sum === o.statistics.sentences) ? 0 : 1);
' "$TMPDIR/hwps.json"
report "--histogram=words_per_sentence -> somme des classes = phrases" $?

# --- 31. char-classes : golden test_fr + somme = caracteres --------------------
"$FSTATS" --json --char-classes tests/fixtures/test_fr.txt > "$TMPDIR/cc.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var c = o.char_classes;
var sum = c.letters + c.digits + c.whitespace + c.punctuation + c.control + c.other;
process.exit((sum === o.statistics.characters && c.letters === 57 && c.digits === 0 &&
  c.whitespace === 12 && c.punctuation === 3 && c.control === 0 && c.other === 0) ? 0 : 1);
' "$TMPDIR/cc.json"
report "--char-classes test_fr.txt -> 57/0/12/3/0/0, somme = 72 caracteres" $?

# --- 32. aggregate + char-classes + histogram : totaux sommes ------------------
"$FSTATS" 'tests/docs/**/*.md' --json-mode=aggregate --char-classes --histogram=line_length > "$TMPDIR/aggs.json" 2>/dev/null
node -e '
var j = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var t = j.totals;
var cl = { letters: 0, digits: 0, whitespace: 0, punctuation: 0, control: 0, other: 0 };
var hc = {};
for (var k = 0; k < j.files.length; k++) {
  var f = j.files[k];
  cl.letters += f.char_classes.letters; cl.digits += f.char_classes.digits;
  cl.whitespace += f.char_classes.whitespace; cl.punctuation += f.char_classes.punctuation;
  cl.control += f.char_classes.control; cl.other += f.char_classes.other;
  f.histogram.classes.forEach(function (c) {
    hc[c.range] = (hc[c.range] || 0) + c.count;
  });
}
var okCC = cl.letters === t.char_classes.letters && cl.digits === t.char_classes.digits &&
  cl.whitespace === t.char_classes.whitespace && cl.punctuation === t.char_classes.punctuation &&
  cl.control === t.char_classes.control && cl.other === t.char_classes.other;
var okH = t.histogram.metric === "line_length" &&
  t.histogram.classes.every(function (c) { return hc[c.range] === c.count; });
process.exit((okCC && okH && !("ngrams" in t)) ? 0 : 1);
' "$TMPDIR/aggs.json"
report "aggregate --char-classes --histogram -> totaux sommés classe par classe" $?

# --- 33. Sortie pipee avec les nouvelles options : aucune sequence ANSI --------
"$FSTATS" --ngrams=2 --histogram=line_length --char-classes tests/fixtures/test_fr.txt > "$TMPDIR/console2.txt" 2>/dev/null
if grep -q $'\x1b' "$TMPDIR/console2.txt"; then OK=1; else OK=0; fi
report "sortie pipee ngrams+histogram+char-classes : aucune sequence ANSI" $OK

# --- 34. --readability --summary-json (valeurs golden sur test_fr.txt) ---------
"$FSTATS" --readability --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/rd.json" 2>/dev/null
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var ap = function (a, b) { return Math.abs(a - b) < 0.001; };
var ok = ap(o.avg_sentence_words, 4.333333) && ap(o.avg_word_chars, 4.615385) &&
  ap(o.pct_long_words, 23.076923) && ap(o.readability_score, 76.62395);
process.exit(ok ? 0 : 1);
' "$TMPDIR/rd.json"
report "--readability --summary-json test_fr.txt -> 4.333333/4.615385/23.076923/76.62395 (epsilon 0.001)" $?

# --- 35. --readability --json : bloc readability avec les 4 clés ---------------
"$FSTATS" --readability --json tests/fixtures/test_fr.txt > "$TMPDIR/rdj.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var r = o.readability;
process.exit((r && "avg_sentence_words" in r && "avg_word_chars" in r &&
  "pct_long_words" in r && "score" in r) ? 0 : 1);' "$TMPDIR/rdj.json"
report "--readability --json -> bloc readability avec les 4 clés" $?

# --- 36. --readability --lexical-stats --summary-json : clés lexicales ET lisibilité
"$FSTATS" --readability --lexical-stats --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/rdlx.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var lex = ("unique_words" in o) && ("entropy_bits_per_word" in o);
var rd = ("avg_sentence_words" in o) && ("readability_score" in o);
process.exit((lex && rd) ? 0 : 1);' "$TMPDIR/rdlx.json"
report "--readability --lexical-stats --summary-json -> clés lexicales ET lisibilité présentes" $?

# --- 37. --readability --csv : 4 lignes summary lisibilité ---------------------
"$FSTATS" --readability --csv tests/fixtures/test_fr.txt > "$TMPDIR/rdc.csv" 2>/dev/null
if grep -q ",summary,,avg_sentence_words,," "$TMPDIR/rdc.csv" &&
   grep -q ",summary,,avg_word_chars,," "$TMPDIR/rdc.csv" &&
   grep -q ",summary,,pct_long_words,," "$TMPDIR/rdc.csv" &&
   grep -q ",summary,,readability_score,," "$TMPDIR/rdc.csv"; then OK=0; else OK=1; fi
report "--readability --csv -> 4 lignes summary lisibilité" $OK

# --- 38. Fichier vide : valeurs 0, score 0 (pas de division par zéro) ----------
"$FSTATS" --readability --summary-json tests/fixtures/empty.txt > "$TMPDIR/rdempty.json" 2>/dev/null
node -e 'var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit((o.avg_sentence_words === 0 && o.avg_word_chars === 0 &&
  o.pct_long_words === 0 && o.readability_score === 0) ? 0 : 1);' "$TMPDIR/rdempty.json"
report "fichier vide --readability --summary-json -> valeurs 0, score 0" $?

# --- 39. Sortie pipee --readability : aucune sequence ANSI ----------------------
"$FSTATS" --readability tests/fixtures/test_fr.txt > "$TMPDIR/rdconsole.txt" 2>/dev/null
if grep -q $'\x1b' "$TMPDIR/rdconsole.txt"; then OK=1; else OK=0; fi
report "sortie pipee --readability : aucune sequence ANSI" $OK

# --- 40. --check : exit 0 + JSON checks[0] ok [actual 3] ------------------------
"$FSTATS" --check --fail-if 'lines>5' --json tests/fixtures/test_fr.txt > "$TMPDIR/chk40.json" 2>/dev/null
ST40=$?
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var c = o.checks[0];
process.exit((o.checks.length === 1 && c.id === "lines" && c.metric === "lines" &&
  c.actual === 3 && c.op === ">" && c.threshold === 5 && c.status === "ok") ? 0 : 1);
' "$TMPDIR/chk40.json"
OK40=$?
if [ $ST40 -eq 0 ] && [ $OK40 -eq 0 ]; then OK=0; else OK=1; fi
report "--check --fail-if lines>5 test_fr.txt -> exit 0, checks[0] ok [entrée complète]" $OK

# --- 41. --check : exit 2 + JSON checks[0] fail [entrée complète] ---------------
"$FSTATS" --check --fail-if 'lines>2' --json tests/fixtures/test_fr.txt > "$TMPDIR/chk41.json" 2>/dev/null
ST41=$?
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var c = o.checks[0];
process.exit((o.checks.length === 1 && c.id === "lines" && c.metric === "lines" &&
  c.actual === 3 && c.op === ">" && c.threshold === 2 && c.status === "fail") ? 0 : 1);
' "$TMPDIR/chk41.json"
OK41=$?
if [ $ST41 -eq 2 ] && [ $OK41 -eq 0 ]; then OK=0; else OK=1; fi
report "--check --fail-if lines>2 test_fr.txt -> exit 2, checks[0] fail" $OK

# --- 42. --check --warn-if : exit 3 + status warn -------------------------------
"$FSTATS" --check --warn-if 'lines>2' --json tests/fixtures/test_fr.txt > "$TMPDIR/chk42.json" 2>/dev/null
ST42=$?
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit((o.checks.length === 1 && o.checks[0].status === "warn") ? 0 : 1);
' "$TMPDIR/chk42.json"
OK42=$?
if [ $ST42 -eq 3 ] && [ $OK42 -eq 0 ]; then OK=0; else OK=1; fi
report "--check --warn-if lines>2 -> exit 3, status warn" $OK

# --- 43. --check --fail-if max_line_length>25 (max 30) : exit 2 -----------------
"$FSTATS" --check --fail-if 'max_line_length>25' tests/fixtures/test_fr.txt > /dev/null 2>&1
if [ $? -eq 2 ]; then OK=0; else OK=1; fi
report "--check --fail-if max_line_length>25 test_fr.txt -> exit 2 [max 30]" $OK

# --- 44. Mode check implicite (sans --check) : exit 2 ---------------------------
"$FSTATS" --fail-if 'lines>2' tests/fixtures/test_fr.txt > /dev/null 2>&1
if [ $? -eq 2 ]; then OK=0; else OK=1; fi
report "mode implicite : --fail-if lines>2 sans --check -> exit 2" $OK

# --- 45. Syntaxe invalide --fail-if : exit 1 + stderr ---------------------------
"$FSTATS" --fail-if lines tests/fixtures/test_fr.txt > /dev/null 2> "$TMPDIR/syn1.err"
ST_A=$?
"$FSTATS" --fail-if 'nope>1' tests/fixtures/test_fr.txt > /dev/null 2> "$TMPDIR/syn2.err"
ST_B=$?
if [ $ST_A -eq 1 ] && grep -q "fail-if" "$TMPDIR/syn1.err" && \
   [ $ST_B -eq 1 ] && grep -q "fail-if" "$TMPDIR/syn2.err"; then OK=0; else OK=1; fi
report "--fail-if sans op / métrique inconnue -> exit 1 + stderr" $OK

# --- 46. Fichier vide : lines>=0 -> exit 2 ; lines>0 -> exit 0 ------------------
"$FSTATS" --check --fail-if 'lines>=0' tests/fixtures/empty.txt > /dev/null 2>&1
ST_A=$?
"$FSTATS" --check --fail-if 'lines>0' tests/fixtures/empty.txt > /dev/null 2>&1
ST_B=$?
if [ $ST_A -eq 2 ] && [ $ST_B -eq 0 ]; then OK=0; else OK=1; fi
report "empty.txt : lines>=0 -> exit 2, lines>0 -> exit 0" $OK

# --- 47. Multi-fichiers : pire statut cumulé (fail > warn > ok) -----------------
"$FSTATS" --check --fail-if 'lines>3' tests/fixtures/test_fr.txt tests/fixtures/bom.txt > /dev/null 2>&1
ST_A=$?
"$FSTATS" --check --fail-if 'lines>1' tests/fixtures/test_fr.txt tests/fixtures/bom.txt > /dev/null 2>&1
ST_B=$?
if [ $ST_A -eq 0 ] && [ $ST_B -eq 2 ]; then OK=0; else OK=1; fi
report "multi-fichiers : lines>3 -> exit 0, lines>1 -> exit 2 [pire statut]" $OK

# --- 48. Baseline --compare + --fail-on-delta -----------------------------------
"$FSTATS" --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/base.json" 2>/dev/null
node -e '
var fs = require("fs");
var s = fs.readFileSync(process.argv[1], "utf8");
fs.writeFileSync(process.argv[2], s.replace("\"lines\": 3", "\"lines\": 1"));
' "$TMPDIR/base.json" "$TMPDIR/base2.json"
"$FSTATS" --compare "$TMPDIR/base.json" --fail-on-delta 'lines>10' tests/fixtures/test_fr.txt > "$TMPDIR/d0.out" 2>/dev/null
ST_A=$?
"$FSTATS" --compare "$TMPDIR/base2.json" --fail-on-delta 'lines>10' tests/fixtures/test_fr.txt > "$TMPDIR/d200.out" 2>/dev/null
ST_B=$?
if [ $ST_A -eq 0 ] && [ $ST_B -eq 2 ] && grep -q "FAIL (delta 200%)" "$TMPDIR/d200.out"; then OK=0; else OK=1; fi
report "baseline : --compare + --fail-on-delta lines>10 -> exit 0 ; baseline lines:1 -> exit 2 [delta 200%]" $OK

# --- 49. --fail-on-delta sans --compare : exit 1 --------------------------------
"$FSTATS" --fail-on-delta 'lines>10' tests/fixtures/test_fr.txt > /dev/null 2> "$TMPDIR/delta.err"
if [ $? -eq 1 ] && grep -q "compare" "$TMPDIR/delta.err"; then OK=0; else OK=1; fi
report "--fail-on-delta sans --compare -> exit 1 + stderr" $OK

# --- 50. Fichier manquant avec --check : exit 1 (fatal prime) -------------------
"$FSTATS" --check --fail-if 'lines>1' absent.txt > /dev/null 2>&1
if [ $? -eq 1 ]; then OK=0; else OK=1; fi
report "--check --fail-if lines>1 absent.txt -> exit 1 [fatal prime]" $OK

# --- 51. Mode analyse sans --check : exit 0 inchangé ----------------------------
"$FSTATS" tests/fixtures/test_fr.txt > "$TMPDIR/ana.out" 2>/dev/null
if [ $? -eq 0 ] && [ -s "$TMPDIR/ana.out" ] && ! grep -q $'\x1b' "$TMPDIR/ana.out"; then OK=0; else OK=1; fi
report "mode analyse test_fr.txt -> exit 0, sortie console sans ANSI" $OK

# --- 52. Delta infini (base 0 -> actual > 0) : exit 2 ; 0 -> 0 : exit 0 ---------
"$FSTATS" --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/baseinf.json" 2>/dev/null
"$FSTATS" --summary-json tests/fixtures/empty.txt > "$TMPDIR/baseemp.json" 2>/dev/null
node -e '
var fs = require("fs");
var s = fs.readFileSync(process.argv[1], "utf8");
fs.writeFileSync(process.argv[2], s.replace("\"words\": 13", "\"words\": 0"));
' "$TMPDIR/baseinf.json" "$TMPDIR/baseinf2.json"
"$FSTATS" --compare "$TMPDIR/baseinf2.json" --fail-on-delta 'words>0' tests/fixtures/test_fr.txt > "$TMPDIR/inf.out" 2>/dev/null
ST_A=$?
"$FSTATS" --compare "$TMPDIR/baseemp.json" --fail-on-delta 'words>0' tests/fixtures/empty.txt > /dev/null 2>&1
ST_B=$?
if [ $ST_A -eq 2 ] && grep -q "delta inf%" "$TMPDIR/inf.out" && [ $ST_B -eq 0 ]; then OK=0; else OK=1; fi
report "delta infini : base 0 -> 13 exit 2 [delta inf%] ; 0 -> 0 exit 0" $OK

# --- 53. Sortie pipee --check : aucune sequence ANSI ----------------------------
"$FSTATS" --check --fail-if 'lines>2' tests/fixtures/test_fr.txt > "$TMPDIR/chkc.out" 2>/dev/null
if grep -q $'\x1b' "$TMPDIR/chkc.out"; then OK=1; else OK=0; fi
report "sortie pipee --check : aucune sequence ANSI" $OK

# --- 54. --summary-json + checks : pas de section, exit 2 appliqué --------------
"$FSTATS" --check --fail-if 'lines>2' --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/sumchk.json" 2>/dev/null
ST54=$?
node -e '
var o = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.exit(("checks" in o) ? 1 : 0);
' "$TMPDIR/sumchk.json"
OK54=$?
if [ $ST54 -eq 2 ] && [ $OK54 -eq 0 ]; then OK=0; else OK=1; fi
report "--summary-json + checks -> pas de section checks, exit 2 appliqué" $OK

# --- 55. Grammaire : espaces autour de l'opérateur + seuil décimal --------------
"$FSTATS" --check --fail-if 'lines > 2.5' tests/fixtures/test_fr.txt > /dev/null 2>&1
ST_A=$?
"$FSTATS" --check --fail-if lines '>' 2 tests/fixtures/test_fr.txt > /dev/null 2>&1
ST_B=$?
if [ $ST_A -eq 2 ] && [ $ST_B -eq 2 ]; then OK=0; else OK=1; fi
report "'--fail-if lines > 2.5' et 3 arguments séparés -> exit 2" $OK

# --- 56. Ids de répétition + aggregate (checks par fichier, pas dans totals) ----
"$FSTATS" --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/base56.json" 2>/dev/null
node -e '
var fs = require("fs");
var s = fs.readFileSync(process.argv[1], "utf8");
fs.writeFileSync(process.argv[2], s.replace("\"lines\": 3", "\"lines\": 1"));
' "$TMPDIR/base56.json" "$TMPDIR/base56b.json"
"$FSTATS" --check --fail-if 'lines>1' --fail-if 'lines>100' --json tests/fixtures/test_fr.txt > "$TMPDIR/ids1.json" 2>/dev/null
ST_A=$?
"$FSTATS" --compare "$TMPDIR/base56b.json" --fail-on-delta 'lines>10' --fail-on-delta 'lines>100' --json tests/fixtures/test_fr.txt > "$TMPDIR/ids2.json" 2>/dev/null
ST_B=$?
"$FSTATS" --check --fail-if 'lines>2' --json-mode=aggregate tests/fixtures/test_fr.txt tests/fixtures/bom.txt > "$TMPDIR/aggrchk.json" 2>/dev/null
ST_C=$?
node -e '
var fs = require("fs");
var o1 = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
var o2 = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
var o3 = JSON.parse(fs.readFileSync(process.argv[3], "utf8"));
var ids1 = o1.checks.map(function (c) { return c.id; }).join(",");
var st1 = o1.checks.map(function (c) { return c.status; }).join(",");
var ids2 = o2.checks.map(function (c) { return c.id; }).join(",");
var ok1 = ids1 === "lines,lines#2" && st1 === "fail,ok";
var ok2 = ids2 === "delta:lines,delta:lines#2";
var ok3 = o3.files[0].checks && o3.files[1].checks && !("checks" in o3.totals);
process.exit((ok1 && ok2 && ok3) ? 0 : 1);
' "$TMPDIR/ids1.json" "$TMPDIR/ids2.json" "$TMPDIR/aggrchk.json"
OK56=$?
if [ $ST_A -eq 2 ] && [ $ST_B -eq 2 ] && [ $ST_C -eq 2 ] && [ $OK56 -eq 0 ]; then OK=0; else OK=1; fi
report "ids lines/lines#2 et delta:lines/delta:lines#2, aggregate sans checks dans totals" $OK


# --- 57. v2.6.1 : 3.14 ne cloture pas une phrase --------------------------------
"$FSTATS" --summary-json tests/fixtures/decimal.txt > "$TMPDIR/dec57.json" 2>/dev/null
node -e '
var cp = require("child_process");
var fs = require("fs");
var o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
var e = cp.spawnSync(process.argv[2], ["-", "--summary-json"], { input: "Le prix est 3.14", encoding: "utf8" });
var oe = JSON.parse(e.stdout);
process.exit((o.sentences === 2 && o.words === 7 && oe.sentences === 1) ? 0 : 1);
' "$TMPDIR/dec57.json" "$FSTATS"
OK57=$?
if [ $OK57 -eq 0 ]; then OK=0; else OK=1; fi
report "3.14 ne cloture pas (decimal.txt 2 phrases ; 3.14 en fin de flux 1 phrase)" $OK

# --- 58. v2.6.1 : point final apres chiffre ; point entoure d'espaces -----------
"$FSTATS" --summary-json tests/fixtures/decimal_end.txt > "$TMPDIR/dec58.json" 2>/dev/null
node -e '
var cp = require("child_process");
var fs = require("fs");
var oa = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
var b = cp.spawnSync(process.argv[2], ["-", "--summary-json"], { input: "3 . 14. Fin.\n", encoding: "utf8" });
var ob = JSON.parse(b.stdout);
process.exit((oa.sentences === 2 && ob.sentences === 3) ? 0 : 1);
' "$TMPDIR/dec58.json" "$FSTATS"
OK58=$?
if [ $OK58 -eq 0 ]; then OK=0; else OK=1; fi
report "'Version 3.' cloture (2 phrases) ; '3 . 14.' espace cloture (3 phrases)" $OK

# --- 59. v2.6.1 : histogramme words_per_sentence coherent (somme = phrases) -----
"$FSTATS" --histogram=words_per_sentence --summary-json tests/fixtures/decimal.txt > "$TMPDIR/dec59.json" 2>/dev/null
node -e '
var fs = require("fs");
var o = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
var sum = o.histogram.classes.reduce(function (a, c) { return a + c.count; }, 0);
process.exit((sum === o.sentences && sum === 2) ? 0 : 1);
' "$TMPDIR/dec59.json"
OK59=$?
if [ $OK59 -eq 0 ]; then OK=0; else OK=1; fi
report "histogramme words_per_sentence sur decimal.txt : somme=2=sentences" $OK

# --- 60. v2.7.0 : --sentence-mode=smart vs basic sur M. Dupont ----------------
node -e '
var cp = require("child_process");
var s = cp.spawnSync(process.argv[1], ["-", "--summary-json", "--sentence-mode=smart"], { input: "M. Dupont est l\u00e0. Bravo.", encoding: "utf8" });
var b = cp.spawnSync(process.argv[1], ["-", "--summary-json", "--sentence-mode=basic"], { input: "M. Dupont est l\u00e0. Bravo.", encoding: "utf8" });
var os = JSON.parse(s.stdout);
var ob = JSON.parse(b.stdout);
process.exit((os.sentences === 2 && ob.sentences === 3) ? 0 : 1);
' "$FSTATS"
OK60=$?
if [ $OK60 -eq 0 ]; then OK=0; else OK=1; fi
report "--sentence-mode stdin M. Dupont est là. Bravo. -> smart 2 phrases, basic 3 phrases" $OK

# --- 61. v2.7.0 : URL protégée en smart (https://ex.com) ----------------------
node -e '
var cp = require("child_process");
var s = cp.spawnSync(process.argv[1], ["-", "--summary-json", "--sentence-mode=smart"], { input: "Visitez https://ex.com maintenant.", encoding: "utf8" });
var b = cp.spawnSync(process.argv[1], ["-", "--summary-json", "--sentence-mode=basic"], { input: "Visitez https://ex.com maintenant.", encoding: "utf8" });
var os = JSON.parse(s.stdout);
var ob = JSON.parse(b.stdout);
process.exit((os.sentences === 1 && ob.sentences === 2) ? 0 : 1);
' "$FSTATS"
OK61=$?
if [ $OK61 -eq 0 ]; then OK=0; else OK=1; fi
report "URL https://ex.com en smart -> 1 phrase, basic 2 phrases" $OK

# --- 62. v2.7.0 : abréviation e.g. deux points avalés -------------------------
node -e '
var cp = require("child_process");
var r = cp.spawnSync(process.argv[1], ["-", "--summary-json", "--sentence-mode=smart"], { input: "e.g. ceci.", encoding: "utf8" });
var o = JSON.parse(r.stdout);
process.exit(o.sentences === 1 ? 0 : 1);
' "$FSTATS"
OK62=$?
if [ $OK62 -eq 0 ]; then OK=0; else OK=1; fi
report "e.g. en smart -> les deux points avalés, 1 phrase" $OK

# --- 63. v2.7.0 : décimale 3.14 toujours gérée en smart -----------------------
node -e '
var cp = require("child_process");
var r = cp.spawnSync(process.argv[1], ["-", "--summary-json", "--sentence-mode=smart"], { input: "Co\u00fbt 3.14 euros.", encoding: "utf8" });
var o = JSON.parse(r.stdout);
process.exit(o.sentences === 1 ? 0 : 1);
' "$FSTATS"
OK63=$?
if [ $OK63 -eq 0 ]; then OK=0; else OK=1; fi
report "3.14 en smart -> décimale pas de clôture, 1 phrase" $OK

# --- 64. v2.7.0 : --sentence-mode=bogus -> exit 1 + stderr --------------------
node -e '
var cp = require("child_process");
var r = cp.spawnSync(process.argv[1], ["--sentence-mode=bogus", "tests/fixtures/test_fr.txt"], { encoding: "utf8" });
process.exit((r.status === 1 && /sentence-mode/.test(r.stderr)) ? 0 : 1);
' "$FSTATS"
OK64=$?
if [ $OK64 -eq 0 ]; then OK=0; else OK=1; fi
report "--sentence-mode=bogus -> exit 1 + stderr sentence-mode" $OK

# --- 65. v2.7.0 : défaut sans option = basic (régression test_fr) -------------
"$FSTATS" --summary-json tests/fixtures/test_fr.txt > "$TMPDIR/def65.json" 2>/dev/null
"$FSTATS" --summary-json --sentence-mode=basic tests/fixtures/test_fr.txt > "$TMPDIR/bas65.json" 2>/dev/null
node -e '
var a = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
var b = JSON.parse(require("fs").readFileSync(process.argv[2], "utf8"));
process.exit((a.sentences === 3 && b.sentences === 3) ? 0 : 1);
' "$TMPDIR/def65.json" "$TMPDIR/bas65.json"
OK65=$?
if [ $OK65 -eq 0 ]; then OK=0; else OK=1; fi
report "test_fr.txt sans option -> 3 phrases et --sentence-mode=basic idem" $OK

# --- 66. v2.7.0 : smart + histogramme words_per_sentence ----------------------
node -e '
var cp = require("child_process");
var r = cp.spawnSync(process.argv[1], ["-", "--summary-json", "--sentence-mode=smart", "--histogram=words_per_sentence"], { input: "M. Dupont est l\u00e0. Bravo.", encoding: "utf8" });
var o = JSON.parse(r.stdout);
var sum = o.histogram.classes.reduce(function (a, c) { return a + c.count; }, 0);
process.exit((sum === 2 && sum === o.sentences) ? 0 : 1);
' "$FSTATS"
OK66=$?
if [ $OK66 -eq 0 ]; then OK=0; else OK=1; fi
report "smart histogram words_per_sentence somme=2=sentences" $OK

# --- 67. v2.7.0 : sortie pipee --sentence-mode=smart sans ANSI ----------------
"$FSTATS" --sentence-mode=smart tests/fixtures/test_fr.txt > "$TMPDIR/smconsole.txt" 2>/dev/null
if grep -q $'\x1b' "$TMPDIR/smconsole.txt"; then OK=1; else OK=0; fi
report "sortie pipee --sentence-mode=smart sans sequence ANSI" $OK
echo ""
echo "RESULTAT : $PASS reussi, $FAIL echec(s)"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
