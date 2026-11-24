# Documentation

Index de la documentation de `fstats`. 🇫🇷 | 🇬🇧 English versions live in
[`en/`](en/README.md) — mirrored from the French canonical sources.

| Fichier | Contenu |
|---|---|
| [CHANGELOG.md](../CHANGELOG.md) | Historique des versions (v2.2.0 → v2.16.2) — [EN](en/CHANGELOG.md) |
| [GUIDE-PEDAGOGIQUE.md](GUIDE-PEDAGOGIQUE.md) | **Guide simple** : comprendre et utiliser fstats sans jargon, exemples commentés — [EN](en/GUIDE-PEDAGOGIQUE.md) |
| [SEMANTIQUE.md](SEMANTIQUE.md) | Spécification technique : sémantique figée des compteurs, formats JSON/CSV détaillés — [EN](en/SEMANTIQUE.md) |
| [ROADMAPFULL.md](ROADMAPFULL.md) | Vision globale : positionnement produit et roadmaps complètes (document historique en français ; l'essentiel est résumé dans les ROADMAP-CIBLE — voir note en tête du fichier) |
| [ROADMAP-CIBLE1.md](ROADMAP-CIBLE1.md) | Cible 1 — « CI / Text Quality Gate » (validée : A v2.2.0, B+C v2.6.0) — [EN](en/ROADMAP-CIBLE1.md) |
| [ROADMAP-CIBLE2.md](ROADMAP-CIBLE2.md) | Cible 2 — « Corpus Profiler » (validée : C2-A v2.3.0, C2-B v2.4.0, C2-C v2.5.0) — [EN](en/ROADMAP-CIBLE2.md) |
| [ROADMAP-CIBLE3.md](ROADMAP-CIBLE3.md) | Cible 3 — « Log Sentinel » — **complète** (v2.11.0) — [EN](en/ROADMAP-CIBLE3.md) |
| [VERIFICATION.md](VERIFICATION.md) | Journal de validation (sorties réelles, historique des vérifications) — [EN](en/VERIFICATION.md) |
| [AUDIT-SECURITE.md](AUDIT-SECURITE.md) | Registre de sécurité/qualité : menaces, constats, backlog et décisions assumées — à lire avant d'analyser des fichiers tiers — [EN](en/AUDIT-SECURITE.md) |

> **Exemples** : le dépôt embarque un corpus de démonstration bilingue dans
> [`exemples/`](../exemples/README.md) — logs SCADA, textes FR/EN, données,
> cas-limites et baseline, avec des commandes vérifiées.

## Parcours de lecture conseillé

1. `README.md` (racine du dépôt) — présentation et utilisation de l'outil.
2. `GUIDE-PEDAGOGIQUE.md` — la prise en main pas à pas, sans jargon.
3. `SEMANTIQUE.md` — la référence technique (sémantique figée, formats).
4. `ROADMAP-CIBLE1.md` — la cible validée (incrément A v2.2.0, B et C v2.6.0) et ses critères
   d'acceptation.
5. `VERIFICATION.md` — le journal des vérifications effectuées (sorties réelles).
6. `ROADMAP-CIBLE2.md` (validée) / `ROADMAP-CIBLE3.md` (complète, v2.11.0) — les cibles.
7. `ROADMAPFULL.md` — la vision d'ensemble de référence.

> **Note (post-restructuration)** : les documents ont été déplacés de la racine
> du dépôt vers `doc/` ; la compilation se fait depuis la racine :
> `fpc -Sg -O2 -Mobjfpc src\fstats.pas` (`-Sg` explicite : GOTO/LABEL du
> matcheur, sinon le build dépend du fpc.cfg de la machine).
