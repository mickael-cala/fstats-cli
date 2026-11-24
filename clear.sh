#!/usr/bin/env bash
# =============================================================================
#  fstats-cli — clear.sh : nettoyage des artefacts de build (Linux)
#
#  Supprime : bin/          (sorties build.sh amd64 / aarch64)
#             fstats / fcmd (binaires racine, tests tests/run.sh)
#             *.ppu / *.o   (racine et src/)
#             src/fstats / src/fcmd (compilations oubli -FE)
#
#  Ne touche à RIEN d'autre (sources, tests, docs, exemples intacts).
#  Exit : 0 toujours (rien à nettoyer = réussite).
#  Usage : chmod +x clear.sh && ./clear.sh
# =============================================================================

echo "Nettoyage des artefacts de compilation fstats-cli..."

echo "  - suppression du dossier bin/ (binaires amd64 / aarch64)"
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
