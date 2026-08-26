# Documentation

Index de la documentation de `fstats`.

| Fichier | Contenu |
|---|---|
| [ROADMAPFULL.txt](ROADMAPFULL.txt) | Vision globale : positionnement produit et roadmaps complètes (texte brut, toutes cibles) |
| [ROADMAP-CIBLE1.md](ROADMAP-CIBLE1.md) | Cible 1 — « CI / Text Quality Gate » (validée : incrément A livré, v2.2.0) |
| [ROADMAP-CIBLE2.md](ROADMAP-CIBLE2.md) | Cible 2 — « Corpus Profiler » (exploration de corpus, vocabulaire, n-grammes) |
| [ROADMAP-CIBLE3.md](ROADMAP-CIBLE3.md) | Cible 3 — « Log Sentinel » (surveillance de logs applicatifs et SCADA/PLC) |
| [VERIFICATION.md](VERIFICATION.md) | Journal de validation (sorties réelles, historique des vérifications) |

## Parcours de lecture conseillé

1. `README.md` (racine du dépôt) — présentation et utilisation de l'outil.
2. `ROADMAP-CIBLE1.md` — la cible livrée en v2.2.0 (incrément A) et ses critères
   d'acceptation.
3. `VERIFICATION.md` — le journal des vérifications effectuées (sorties réelles).
4. `ROADMAP-CIBLE2.md` / `ROADMAP-CIBLE3.md` — les cibles suivantes.
5. `ROADMAPFULL.txt` — la vision d'ensemble de référence.

> **Note (post-restructuration)** : les documents ont été déplacés de la racine
> du dépôt vers `doc/` ; la compilation se fait depuis la racine :
> `fpc -O2 -Mobjfpc src\fstats.pas`.
