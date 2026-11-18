# LAFLEURMUSIC téléphone — plan 7 « mode clair » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** l'appli suit le réglage clair / sombre du téléphone : mode sombre (l'affichage d'aujourd'hui) ou mode clair (fond blanc, logo noir, détails rose), sans bouton dans l'appli.

**Architecture:** les couleurs codées en dur passent par des jetons de thème (`LafleurColors` en `ThemeExtension`, une version sombre = valeurs actuelles, une version claire = maquette 5). `MaterialApp` reçoit `theme` + `darkTheme` + `themeMode: ThemeMode.system`. Le logo existe en blanc et en noir.

**Tech Stack:** Flutter `ThemeExtension`, `MediaQuery.platformBrightness`, goldens doublés (sombre / clair).

**Spec:** spec §8 (« Mode clair », automatique) · Maquette validée : `maquettes/5-mode-clair.png` (écrans 1 à 4 en clair).

## Global Constraints

- Couleurs du mode clair (maquette 5) : fond `#FFFFFF`, barres `#F3F3F3`, texte `#111111`, texte secondaire `#6E6E6E`, traits `#E4E4E4` / `#EEEEEE`, bordures `#CFCFCF`, grisé `#B8B8B8`, rose `#F26EF2` inchangé, texte sur rose `#111`. Mode sombre : valeurs d'aujourd'hui, inchangées (aucun golden sombre ne doit bouger).
- Logo : `assets/logo-texte-grand.png` (blanc) en sombre, `assets/logo-texte-grand-noir.png` (nouveau, même dessin en noir) en clair.
- Les écrans sans maquette claire (écrans 5 à 11, Mode Classic, tablette) appliquent les mêmes jetons ; **captures claires de chacun montrées à Johnny avant la fin du plan** (pas de nouveau dessin, seulement les couleurs).
- Barre d'état et barre de navigation Android lisibles dans les deux modes.
- Commits en anglais, auteur Jonlekern, sans Co-Authored-By ni mention d'IA. Branche `plan-7-light`.

## Review Focus

1. **Changer de mode pendant que l'appli est ouverte** (centre de contrôle) : tout l'écran change tout de suite, la lecture continue — test en tâche 2.
2. **Couleur restée en dur** quelque part (texte blanc sur fond blanc) : recherche de toutes les couleurs littérales hors du thème — vérification en tâche 1.
3. **Pochette blanche sur fond blanc** : une fine bordure `#E4E4E4` autour des pochettes en mode clair — test en tâche 2.
4. **Texte sur rose** reste `#111` dans les deux modes (contraste) — test en tâche 2.
5. **Goldens sombres inchangés** au pixel près — vérification en tâche 3.

---

### Task 1: Jetons de couleur

**Files:** Create `lib/theme/lafleur_colors.dart`, `assets/logo-texte-grand-noir.png` · Modify `lib/theme/*`, tous les widgets qui utilisent une couleur littérale (`lib/ui/**`) · Test `test/theme/colors_test.dart`

- [ ] Step 1: inventaire des couleurs littérales (`grep -rn "Color(0x" lib/ui lib/theme`) dans le rapport ; chacune remplacée par un jeton ; test qui échoue si une couleur littérale réapparaît sous `lib/ui` (hors pochettes de démo). Goldens sombres inchangés. Commit `refactor: color tokens for light and dark`.

### Task 2: Mode clair

**Files:** Modify `lib/main.dart`, `lib/theme/lafleur_theme.dart`, `lib/ui/phone/*`, `lib/ui/*` (logo selon la luminosité, bordure des pochettes), `ios/Runner/Info.plist` (barre d'état), Android styles · Test widget + goldens clairs

- [ ] Step 1: tests (points 1, 3, 4) ; goldens clairs des écrans 1 à 4 comparés à la maquette 5. Échec, implémentation, verts. Commit `feat: light mode following the phone setting`.

### Task 3: Tous les écrans en clair

- [ ] Step 1: goldens clairs des écrans 5 à 11, Mode Classic, tablette ; captures simulateur claires et sombres **montrées à Johnny** ; ajustements de couleur seulement s'il le demande.
- [ ] Step 2: point 5 (goldens sombres inchangés), CI verte, README et checklist. Commit `docs: plan 7 light mode status`.
