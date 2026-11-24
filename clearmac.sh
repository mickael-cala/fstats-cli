#!/bin/zsh
# =============================================================================
#  fstats-cli — clearmac.sh : nettoyage des artefacts de build (macOS, zsh)
#
#  Supprime : bin/          (sorties buildmac.sh aarch64 / x86_64)
#             fstats / fcmd (binaires racine)
#             *.ppu / *.o   (racine et src/)
#             src/fstats / src/fcmd (compilations oubli -FE)
#
#  Ne touche à RIEN d'autre (sources, tests, docs, exemples intacts).
#  Exit : 0 toujours (rien à nettoyer = réussite).
#  Usage : chmod +x clearmac.sh && ./clearmac.sh
# =============================================================================

echo "Nettoyage des artefacts de compilation fstats-cli..."

echo "  - suppression du dossier bin/ (binaires aarch64 / x86_64)"
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
