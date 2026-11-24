#!/bin/bash
# =============================================================================
#  fstats-cli — buildmac-intel.sh : compilation macOS Intel (bash)
#
#  Cible    : x86_64 (Intel 64, natif sur Mac Intel) -> bin/x86_64/fstats+fcmd
#
#  Règles   : -Sg est OBLIGATOIRE (goto dans fstats_lex.pas, leçon 13)
#             écrit pour le bash 3.2 des vieux macOS (aucun bashisme récent) :
#             utilisable tel quel sur Lion → Monterey, zsh non requis.
#  Exit     : 0 = cible compilée, 1 = échec
#  Requis   : Free Pascal 3.2.2+ (installateur officiel ou MacPorts/Fink).
#  Usage    : chmod +x buildmac-intel.sh && ./buildmac-intel.sh
#             (ou : bash buildmac-intel.sh)
# =============================================================================

set -u

# --- 1. Localisation du compilateur ------------------------------------------
FPC="${FPC:-}"
if [ -z "$FPC" ]; then
    if command -v fpc >/dev/null 2>&1; then
        FPC="fpc"
    elif [ -x /usr/local/bin/fpc ]; then
        FPC="/usr/local/bin/fpc"           # installateur officiel FPC (Intel)
    elif [ -x /opt/local/bin/fpc ]; then
        FPC="/opt/local/bin/fpc"            # MacPorts
    elif [ -x /sw/bin/fpc ]; then
        FPC="/sw/bin/fpc"                   # Fink (très vieux Macs)
    else
        echo "[ERREUR] Compilateur Free Pascal introuvable."
        echo "         Installez fpc puis relancez, ou definissez"
        echo "         FPC=/chemin/vers/fpc ./buildmac-intel.sh"
        exit 1
    fi
fi
echo "Compilateur : $FPC"

# --- 2. Compilation de la cible x86_64 ---------------------------------------
sortie="bin/x86_64"
mkdir -p "$sortie"
echo
echo "=== macOS Intel (x86_64) ==="
echo "    sortie : $sortie/"

if ! "$FPC" -Px86_64 -Tdarwin -Sg -O2 -Mobjfpc \
        -FE"$sortie" -FU"$sortie" src/fstats.pas; then
    echo
    echo "    [ÉCHEC ] compilation de fstats impossible — voir ci-dessus."
    exit 1
fi

if ! "$FPC" -Px86_64 -Tdarwin -Sg -O2 -Mobjfpc \
        -FE"$sortie" -FU"$sortie" src/fcmd.pas; then
    echo
    echo "    [ÉCHEC ] compilation de fcmd impossible — voir ci-dessus."
    exit 1
fi

echo "    CIBLE OK : $sortie/fstats + $sortie/fcmd"
echo
echo "RÉCAP : binaires prêts dans $sortie/."
exit 0
