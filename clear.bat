@echo off
setlocal
rem ==========================================================================
rem  fstats-cli -- clear.bat : nettoyage des artefacts de build (Windows)
rem
rem  Supprime : bin\ (sorties build.bat 32/64 bits)
rem             fstats.exe / fcmd.exe (racine, tests run.bat)
rem             *.ppu / *.o (racine et src\)
rem             src\fstats.exe / src\fcmd.exe (compilations oubli -FE)
rem
rem  Ne touche a RIEN d'autre (sources, tests, docs, exemples intacts).
rem  Exit : 0 toujours (rien a nettoyer = succes).
rem  Messages ASCII seulement (codepage indifferrent).
rem ==========================================================================

echo Nettoyage des artefacts de compilation fstats-cli...

if exist "bin\" (
    echo   - suppression du dossier bin\ ^(binaires 32/64 bits^)
    rmdir /s /q "bin"
)

echo   - suppression fstats.exe / fcmd.exe racine
del /q fstats.exe fcmd.exe 2>nul

echo   - suppression src\fstats.exe / src\fcmd.exe
del /q src\fstats.exe src\fcmd.exe 2>nul

echo   - suppression *.ppu / *.o racine
del /q *.ppu *.o 2>nul

echo   - suppression src\*.ppu / src\*.o
del /q src\*.ppu src\*.o 2>nul

echo Nettoyage termine. Sources, tests, docs et exemples intacts.
exit /b 0
