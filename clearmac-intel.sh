#!/bin/bash
# =============================================================================
#  fstats-cli — clearmac-intel.sh : nettoyage des artefacts (macOS Intel, bash)
#
#  Supprime : bin/          (sorties binaires)
#             fstats / fcmd (binaires racine)
#             *.ppu / *.o   (racine et src/)
#             src/fstats / src/fcmd (compilations oubli -FE)
#
#  Ne touche à RIEN d'autre (sources, tests, docs, exemples intacts).
#  Exit : 0 toujours (rien à nettoyer = réussite).
#  Usage : chmod +x clearmac-intel.sh && ./clearmac-intel.sh
# =============================================================================

echo "Nettoyage des artefacts de compilation fstats-cli..."

echo "  - suppression du dossier bin/"
rm -rf bin

echo "  - suppression fstats / fcmd racine"
rm -f fstats fcmd

echo "  - suppression src/fstats / src/fcmd"
rm -f src/fstats src/fcmd

echo "  - suppression *.ppu / *.o racine"
rm -f *.ppu *.o

echo "  - suppression src/*.ppu / src/*.o"
rm -f src/*.ppu src/*.o

echo "Nettoyage terminé. Sources, tests, docs et exemples intacts."
exit 0
