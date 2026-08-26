# Documentation

Index de la documentation de `fstats`.

| Fichier | Contenu |
|---|---|
| [GUIDE-PEDAGOGIQUE.md](GUIDE-PEDAGOGIQUE.md) | **Guide simple** : comprendre et utiliser fstats sans jargon, exemples commentés |
| [SEMANTIQUE.md](SEMANTIQUE.md) | Spécification technique : sémantique figée des compteurs, formats JSON/CSV détaillés |
| [ROADMAPFULL.md](ROADMAPFULL.md) | Vision globale : positionnement produit et roadmaps complètes (Markdown, toutes cibles) |
| [ROADMAP-CIBLE1.md](ROADMAP-CIBLE1.md) | Cible 1 — « CI / Text Quality Gate » (validée : incrément A livré, v2.2.0) |
| [ROADMAP-CIBLE2.md](ROADMAP-CIBLE2.md) | Cible 2 — « Corpus Profiler » (validée : C2-A v2.3.0, C2-B v2.4.0, C2-C v2.5.0) |
| [ROADMAP-CIBLE3.md](ROADMAP-CIBLE3.md) | Cible 3 — « Log Sentinel » (surveillance de logs applicatifs et SCADA/PLC) |
| [VERIFICATION.md](VERIFICATION.md) | Journal de validation (sorties réelles, historique des vérifications) |

## Parcours de lecture conseillé

1. `README.md` (racine du dépôt) — présentation et utilisation de l'outil.
2. `GUIDE-PEDAGOGIQUE.md` — la prise en main pas à pas, sans jargon.
3. `SEMANTIQUE.md` — la référence technique (sémantique figée, formats).
4. `ROADMAP-CIBLE1.md` — la cible livrée en v2.2.0 (incrément A) et ses critères
   d'acceptation.
5. `VERIFICATION.md` — le journal des vérifications effectuées (sorties réelles).
6. `ROADMAP-CIBLE2.md` (validée) / `ROADMAP-CIBLE3.md` — les cibles.
7. `ROADMAPFULL.md` — la vision d'ensemble de référence.

> **Note (post-restructuration)** : les documents ont été déplacés de la racine
> du dépôt vers `doc/` ; la compilation se fait depuis la racine :
> `fpc -O2 -Mobjfpc src\fstats.pas`.
