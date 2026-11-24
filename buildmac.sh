#!/bin/zsh
# =============================================================================
#  fstats-cli — buildmac.sh : compilation macOS (zsh, Apple Silicon récent)
#
#  Cibles   : aarch64 (Apple Silicon, natif) -> bin/aarch64/fstats + fcmd
#             x86_64  (Intel, cross optionnel) -> bin/x86_64/fstats + fcmd
#
#  Règles   : -Sg est OBLIGATOIRE (goto dans fstats_lex.pas, leçon 13)
#             une cible indisponible est signalée puis ignorée : le script
#             continue et récapitule à la fin.
#  Exit     : 0 = toutes les cibles compilées, 1 = au moins un échec
#  Requis   : Free Pascal 3.2.2+ et macOS récent avec zsh (/bin/zsh).
#             Le cross x86_64 sur Apple Silicon exige une chaîne FPC adaptée.
#  Usage    : chmod +x buildmac.sh && ./buildmac.sh   (ou : zsh buildmac.sh)
#  Note     : script volontairement limité au sous-ensemble POSIX commun
#             zsh/bash (pas de bashisme ni de zshisme) pour rester auditable.
# =============================================================================

set -u

# --- 1. Localisation du compilateur ------------------------------------------
FPC="${FPC:-}"
if [ -z "$FPC" ]; then
    if command -v fpc >/dev/null 2>&1; then
        FPC="fpc"
    elif [ -x /opt/homebrew/bin/fpc ]; then
        FPC="/opt/homebrew/bin/fpc"        # Homebrew Apple Silicon
    elif [ -x /usr/local/bin/fpc ]; then
        FPC="/usr/local/bin/fpc"           # Homebrew Intel / installateur FPC
    elif [ -x /opt/fpc/bin/fpc ]; then
        FPC="/opt/fpc/bin/fpc"
    else
        echo "[ERREUR] Compilateur Free Pascal introuvable."
        echo "         Installez fpc (ex : brew install fpc) puis relancez,"
        echo "         ou definissez FPC=/chemin/vers/fpc ./buildmac.sh"
        exit 1
    fi
fi
echo "Compilateur : $FPC"

OK=0
KO=0

# --- 2. Une cible = une fonction ---------------------------------------------
# $1 = description, $2 = architecture FPC (-P), $3 = sous-dossier de bin/
compiler_cible() {
    desc="$1"
    arch="$2"
    dossier="$3"
    sortie="bin/$dossier"

    mkdir -p "$sortie"
    echo
    echo "=== $desc ==="
    echo "    sortie : $sortie/"

    # Cible 1 : fstats
    if ! "$FPC" -P"$arch" -Tdarwin -Sg -O2 -Mobjfpc \
            -FE"$sortie" -FU"$sortie" src/fstats.pas; then
        echo
        echo "    [ÉCHEC ] $desc : compilateur ou unites indisponibles pour"
        echo "    cette cible. Les autres cibles continuent."
        rmdir "$sortie" 2>/dev/null || true    # purge le dossier s'il reste vide
        KO=$((KO + 1))
        return
    fi
    # Cible 2 : fcmd (le compagnon)
    if ! "$FPC" -P"$arch" -Tdarwin -Sg -O2 -Mobjfpc \
            -FE"$sortie" -FU"$sortie" src/fcmd.pas; then
        echo
        echo "    [ÉCHEC ] $desc : fcmd n'a pas pu etre compile."
        echo "    Les autres cibles continuent."
        rmdir "$sortie" 2>/dev/null || true    # purge le dossier s'il reste vide
        KO=$((KO + 1))
        return
    fi

    echo "    CIBLE OK : $sortie/fstats + $sortie/fcmd"
    OK=$((OK + 1))
}

# --- 3. Compilation des deux cibles -----------------------------------------
compiler_cible "macOS Apple Silicon (aarch64)" "aarch64" "aarch64"
compiler_cible "macOS Intel (x86_64, cross)"   "x86_64"  "x86_64"

# --- 4. Récapitulatif --------------------------------------------------------
echo
if [ "$KO" -eq 0 ]; then
    echo "RÉCAP : 2/2 cibles compilées. Binaires dans bin/aarch64/ et bin/x86_64/."
    exit 0
fi
echo "RÉCAP : $OK cible(s) compilée(s), $KO cible(s) en échec — voir ci-dessus."
exit 1
