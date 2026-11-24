#!/usr/bin/env bash
# =============================================================================
#  fstats-cli — build.sh : compilation Linux multi-cibles (amd64 + aarch64)
#
#  Cibles   : amd64   (x86_64 natif sur PC 64 bits) -> bin/amd64/fstats + fcmd
#             aarch64 (ARM 64, cross ou natif)     -> bin/aarch64/fstats + fcmd
#
#  Règles   : -Sg est OBLIGATOIRE (goto dans fstats_lex.pas, leçon 13)
#             une cible indisponible est signalée puis ignorée : le script
#             continue et récapitule à la fin.
#  Exit     : 0 = toutes les cibles compilées, 1 = au moins un échec
#  Requis   : Free Pascal 3.2.2+ (fpc dans le PATH ou chemin dans $FPC).
#             La cible aarch64 depuis un PC amd64 exige une chaîne FPC
#             « cross » (paquets fpc-aarch64-linux ou équivalent).
#  Usage    : chmod +x build.sh && ./build.sh        (ou : bash build.sh)
# =============================================================================

set -u

# --- 1. Localisation du compilateur ------------------------------------------
FPC="${FPC:-}"
if [ -z "$FPC" ]; then
    if command -v fpc >/dev/null 2>&1; then
        FPC="fpc"
    elif [ -x /usr/local/bin/fpc ]; then
        FPC="/usr/local/bin/fpc"
    elif [ -x /usr/bin/fpc ]; then
        FPC="/usr/bin/fpc"
    else
        echo "[ERREUR] Compilateur Free Pascal introuvable."
        echo "         Installez fpc (ex : apt install fpc) puis relancez,"
        echo "         ou definissez FPC=/chemin/vers/fpc ./build.sh"
        exit 1
    fi
fi
echo "Compilateur : $FPC"

OK=0
KO=0

# --- 2. Une cible = une fonction ---------------------------------------------
# $1 = description, $2 = architecture FPC (-P), $3 = sous-dossier de bin/
compiler_cible() {
    local desc="$1" arch="$2" dossier="$3"
    local sortie="bin/$dossier"

    mkdir -p "$sortie"
    echo
    echo "=== $desc ==="
    echo "    sortie : $sortie/"

    # Cible 1 : fstats
    if ! "$FPC" -P"$arch" -Tlinux -Sg -O2 -Mobjfpc \
            -FE"$sortie" -FU"$sortie" src/fstats.pas; then
        echo
        echo "    [ÉCHEC ] $desc : compilateur ou unites indisponibles pour"
        echo "    cette cible (paquet cross fpcompiler manquant ?)."
        echo "    Les autres cibles continuent."
        rmdir "$sortie" 2>/dev/null || true    # purge le dossier s'il reste vide
        KO=$((KO + 1))
        return
    fi
    # Cible 2 : fcmd (le compagnon)
    if ! "$FPC" -P"$arch" -Tlinux -Sg -O2 -Mobjfpc \
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
compiler_cible "Linux amd64 (x86_64)"   "x86_64"  "amd64"
compiler_cible "Linux aarch64 (ARM 64)"  "aarch64" "aarch64"

# --- 4. Récapitulatif --------------------------------------------------------
echo
if [ "$KO" -eq 0 ]; then
    echo "RÉCAP : 2/2 cibles compilées. Binaires dans bin/amd64/ et bin/aarch64/."
    exit 0
fi
echo "RÉCAP : $OK cible(s) compilée(s), $KO cible(s) en échec — voir ci-dessus."
exit 1
