# LAFLEURMUSIC téléphone — plan 6 « Mode Classic » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** dans Réglages, choisir **Mode normal** (l'appli d'aujourd'hui) ou **Mode Classic** : un menu façon iPod en haut et une grande molette cliquable en bas, qu'on tourne du doigt.

**Architecture:** un `ClassicShell` remplace le `PhoneShell` quand le réglage est sur Classic. Il réutilise les mêmes données (bibliothèque fusionnée, lecteur, file, garder) ; seule la façon de naviguer change. La molette est un widget à part (`ClickWheel`) qui transforme un geste circulaire en crans.

**Tech Stack:** Flutter (`GestureDetector`, `HapticFeedback.selectionClick`), aucune dépendance nouvelle.

**Spec:** spec §2, §4.5, §8 (« Molette = Mode Classic ») · Maquette validée : `maquettes/6-molette.png` **version A**.

## Global Constraints

- Visuel : version A de `maquettes/6-molette.png` (écran menu + molette). Écran En cours en Mode Classic et choix du mode dans Réglages : **maquette validée** `maquettes/12-classic.png` (oui de Johnny le 19.11.2026) — A : tourner = volume (barre blanche) ; B : appui au milieu = avancer dans le morceau (losange rose, retour au volume par un nouvel appui ou après 3 s) ; C : Réglages › Affichage, « Mode normal / Mode Classic ».
- Molette : tourner dans le sens des aiguilles = descendre, l'autre sens = monter ; un cran tous les 15° ; petit clic (vibration légère) à chaque cran ; rond du milieu = choisir ; MENU (haut de l'anneau) = retour ; ⏮ / ⏭ (côtés) = morceau précédent / suivant ; ▶︎❙❙ (bas) = lecture / pause. Sur l'écran En cours, tourner = volume (comme l'iPod), un appui au milieu passe en mode « avancer dans le morceau ».
- Menu du Mode Classic (dans cet ordre) : Cover Flow, Artistes, Albums, Morceaux, Playlists, Top 100, Sur mon iPhone / Sur mon téléphone, En cours, Réglages.
- Le mode choisi est gardé dans `settings.json` ; Mode normal par défaut.
- Accessibilité : chaque zone de la molette a un libellé pour VoiceOver / TalkBack ; un appui simple sur une ligne du menu marche aussi.
- Commits en anglais, auteur Jonlekern, sans Co-Authored-By ni mention d'IA. Branche `plan-6-classic`.

## Review Focus

1. **Geste très rapide** (un tour complet en 0,2 s) : chaque cran compté, pas de saut ni de retour en arrière — test en tâche 1.
2. **Doigt qui passe par le centre** pendant un tour : pas de choix déclenché par erreur — test en tâche 1.
3. **Liste de 5 000 morceaux** : la sélection suit la molette sans saccade, la liste défile pour garder la ligne choisie visible — test en tâche 2.
4. **Passer de Classic à normal pendant la lecture** : la musique continue, la file est la même — test en tâche 3.
5. **Téléphone couché en Mode Classic** : Cover Flow comme en mode normal — test en tâche 2.

---

### Task 1: La molette

**Files:** Create `lib/ui/classic/click_wheel.dart` · Test `test/ui/classic/click_wheel_test.dart`, golden

**Interfaces:**
- Produces : `ClickWheel({required void Function(int steps) onRotate, VoidCallback? onSelect, onMenu, onPrevious, onNext, onPlayPause})` ; l'angle est suivi autour du centre, un cran = 15°, `onRotate(+1/-1)` par cran avec `HapticFeedback.selectionClick()` ; une tape sans rotation sur une zone déclenche son bouton.

- [ ] Step 1: tests (crans, sens, points 1-2, tapes). Échec, implémentation, verts ; golden comparé à la maquette 6 A. Commit `feat: click wheel widget`.

### Task 2: Le Mode Classic

**Files:** Create `lib/ui/classic/classic_shell.dart`, `lib/ui/classic/classic_menu.dart` · Modify `lib/main.dart` · Test widget + goldens

**Interfaces:**
- Produces : écran du haut (titre de la liste, ▶︎ et batterie stylisés, lignes, ligne choisie en rose) ; la molette déplace la ligne choisie, le milieu ouvre, MENU revient ; Albums / Artistes / Morceaux / Playlists / Top 100 lisent les mêmes listes que le mode normal ; « En cours » ouvre l'écran En cours Classic (tâche 3).

- [ ] Step 1: tests (navigation complète à la molette, points 3 et 5). Échec, implémentation, verts ; goldens ; captures simulateur. Commit `feat: Classic mode navigation`.

### Task 3: En cours en Mode Classic et choix du mode

**Files:** Create `lib/ui/classic/classic_now.dart`, `maquettes/12-classic.png` (déjà faite) · Modify `lib/ui/phone/accounts_screen.dart` (Réglages : section « MODE » avec « Normal / Classic »), `lib/settings.dart`, `lib/l10n/strings.dart` · Test widget + goldens

- [x] Step 1: maquette validée (`maquettes/12-classic.png`).
- [ ] Step 2: tests (volume à la molette, avancer dans le morceau, point 4, réglage gardé). Échec, implémentation, verts ; goldens ; captures. Commit `feat: Classic now playing and mode setting`.

### Task 4: Bout en bout et documents

- [ ] Step 1: essai d'intégration : passer en Classic, choisir un album à la molette, jouer, revenir en mode normal ; simulateur iPhone + job Android ; CI verte.
- [ ] Step 2: README et checklist. Commit `docs: plan 6 Classic mode status`.
