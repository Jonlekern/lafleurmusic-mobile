# LAFLEURMUSIC téléphone — plan 12 « retours de l'iPhone » Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** corriger ce que Johnny a vu sur son iPhone le 21–22.11.2026 : numéros de morceaux cassés en texte agrandi ; avancer la musique au doigt depuis le mini-lecteur et le mode Classic ; barre de son du Classic seulement pendant le réglage ; tour rose de la molette qui suit le morceau.

**Architecture:** réutiliser `SeekArea` (lib/ui/seek_area.dart : toucher saute, glisser suit le doigt, un seul saut au lâcher) pour le fil du mini-lecteur et la barre de progression du Classic. La molette (`click_wheel.dart`) reçoit une fraction de progression au lieu d'un arc fixe. `ClassicNow` montre la barre de son pendant 2 s après un cran de volume.

**Tech Stack:** Flutter.

**Spec:** captures annotées de Johnny (21–22.11.2026) + maquette validée `maquettes/20-classic-progression.png` (Johnny « Oui, go », 22.11.2026).

## Global Constraints

- Numéros : la colonne a la largeur du plus grand numéro de la liste **à la taille de texte du téléphone** (`MediaQuery.textScalerOf`), une seule ligne (`maxLines: 1`, `softWrap: false`), alignée à droite, chiffres de même largeur (`FontFeature.tabularFigures()`). À taille normale et numéros ≤ 2 chiffres, les goldens existants ne changent pas (sinon : justifier la différence au contrôleur).
- Mini-lecteur (debout et couché) : le fil rose reste de 3 points ; une bande de toucher de 28 points de haut centrée dessus (invisible) ; toucher = saute ; glisser = le fil suit le doigt avec un rond rose de 14 points et une étiquette du temps (fond `context.colors.text`, texte inverse, 11 pt gras, ex. « 2:29 ») au-dessus du rond, la musique saute une seule fois au lâcher. Toucher le reste du mini-lecteur ouvre toujours « En cours ».
- Classic « En cours » : la barre de progression se touche / se glisse (SeekArea), avec un rond rose de 18 points sur la position (maquette 20 A). L'appui central + molette pour avancer (losange, mode « scrub ») reste comme aujourd'hui.
- Classic : la barre de son est cachée (place gardée, la mise en page ne bouge pas) ; elle apparaît à chaque cran de volume à la molette et s'efface **2 s** après le dernier cran. Le lecteur d'écran garde l'accès au volume (sémantique toujours présente).
- Molette : l'arc rose part de midi (MENU) et couvre `fraction × 360°` dans le sens des aiguilles d'une montre, fraction = position / durée du morceau en cours ; pas de morceau ou durée 0 → pas d'arc. Sur tous les écrans Classic où la molette est dessinée. Mise à jour au rythme de la position du lecteur (pas de timer en plus).
- Mode sombre et clair : goldens des deux (`-light`).
- Commits en anglais, auteur Jonlekern, sans Co-Authored-By ni mention d'IA. Branche `classic-progress`.

## Review Focus

1. **Texte du téléphone très agrandi (×1,6) et numéros à 3 chiffres (Top 100, playlist de 120 morceaux)** : chaque numéro sur une ligne, rien coupé — test tâche 1.
2. **Glisser sur le fil du mini-lecteur** ne doit pas ouvrir « En cours » ni faire défiler la liste au-dessus ; un toucher ailleurs ouvre toujours « En cours » — test tâche 2.
3. **Morceau changé pendant un glisser** (fin du morceau) : pas de saut dans le mauvais morceau au lâcher — test tâche 2.
4. **Tourner la molette en continu** : la barre de son reste visible tant qu'on tourne, s'efface 2 s après le dernier cran ; quitter l'écran pendant ce temps → pas d'erreur de timer — test tâche 3.
5. **Durée inconnue (flux sans durée)** : pas d'arc, barres sans action, pas de division par zéro — test tâche 3.

---

### Task 1: Les numéros tiennent

**Files:** Modify `lib/ui/phone/album_screen.dart` (`PhoneTrackRows` et la ligne de morceau) · Test `test/ui/phone/track_number_test.dart`

- [ ] Step 1: tests : textScaler 1,6 avec numéros 9, 13, 15, 120 → chaque numéro tient sur une ligne (hauteur du Text = une ligne) et n'est pas tronqué ; à 1,0 la colonne fait au moins 20 points (rien ne bouge pour 1–2 chiffres). Implémentation, tests + goldens existants verts. Commit `fix: track numbers stay on one line with large text`.

### Task 2: Avancer au doigt

**Files:** Modify `lib/ui/phone/mini_player.dart`, `lib/ui/classic/classic_now.dart`, au besoin `lib/ui/seek_area.dart` (sans casser ses usages) · Test `test/ui/phone/mini_player_seek_test.dart`, `test/ui/classic/classic_now_seek_test.dart` · Goldens : `phone-20c` (mini-lecteur pendant un glisser, rond + « 2:29 ») sombre et `-light`.

- [ ] Step 1: tests des points 2 et 3 de la Review Focus ; toucher la barre Classic → un seul `seek` au bon endroit ; glisser → un seul `seek` au lâcher ; rond présent sur la barre Classic. Implémentation, verts. Commit `feat: seek by finger from the mini player and in Classic mode`.

### Task 3: Molette et barre de son du Classic

**Files:** Modify `lib/ui/classic/click_wheel.dart` (paramètre `double? progress`), `lib/ui/classic/classic_now.dart`, les écrans Classic qui dessinent la molette (`classic_shell.dart`, `classic_coverflow.dart`…) · Test `test/ui/classic/classic_progress_test.dart` · Goldens Classic existants mis à jour (l'arc change) + `classic-20a/b` (maquette 20 A et B) sombre et `-light`.

- [ ] Step 1: tests des points 4 et 5 ; arc absent sans morceau ; peintre : angle balayé = fraction × 2π depuis −π/2. Goldens régénérés et comparés à la maquette 20. Commit `feat: the click wheel ring follows the song; volume bar only while turning`.
