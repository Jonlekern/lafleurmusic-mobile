# Task 4 report: display mode and account order

## What
- `lib/ui/phone/display_choice.dart` (new): `AppScope.chooseDisplay / toggleCustom` set `AppSettings` (displayMode, oneAccount, customAccounts), call `saveSettings`, then `libraryView.settingsChanged()`. First Perso checks every account; the last checked account cannot be unchecked.
- `LibraryView.revision` (ValueNotifier, bumped by `settingsChanged`) so the Home chips follow a change made on the Accounts screen.
- Accounts screen (maquette 2 screen 6): the AFFICHAGE segment (Un compte / Tout / Perso) is live (no more "bientôt"), the checkboxes show only in Perso and are tappable, the grip drag already saved `position` (`Accounts.reorder`; LibraryView re-emits on the order change). `AccountsDisplay` enum removed, `DisplayMode` used.
- Home chips (maquette 1 screen 1): "Tout ▾" (label becomes "Perso ▾" in Perso) opens a small menu Tout / Perso; one chip per account = Un compte. Active chip is pink-outlined.
- Decisions: chips stay visible with a single account (Tout + that account); in Un compte there are no checkboxes in settings (the account is picked with the Home chips); local files are always visible (LibraryView/db from Task 1, covered by a test); Q7 untouched (only lists are filtered).

## Tests
Written after the implementation (not strict red/green first). Added in `test/ui/accounts_widget_test.dart`: mode switch saved + checkboxes only in Perso; last checked stays; drag order saved (positions 0,1,2); Home one album per account; account chip = Un compte, saved, lists refresh; Tout ▾ chooser, Perso with two of three accounts; mode set on the Accounts screen updates Home; local file visible in every mode. Fixture: `pumpAccounts(view: true)` gives a real LibraryView, `f.settings`, `f.saves`.
- `flutter analyze`: no issues. `flutter test --exclude-tags golden`: 692 passed, 3 skipped. `flutter test --tags golden`: 19 passed.
- Goldens: `phone-6.png` regenerated (legit: now shows Perso with Plex unchecked as in the mockup; before it was Un compte with greyed checks). New `phone-1-one-account.png` (Home, Jellyfin chip active). `phone-1.png` unchanged (default Tout).
- Simulator (demo mode) in `shots/`: task-4-home-tout.png, task-4-home-chooser.png, task-4-settings-perso.png, task-4-home-perso.png. Demo has no LibraryView, so lists do not filter there (tracks use a fake account id); chips and settings work.

## Concerns
- Dart format of `test lib` briefly touched unrelated files; reverted, only task files committed.
- Perso with every account later removed: customAccounts keeps stale ids (visibleOf ignores them).

## Fix round 1
1. Stale ids in Perso: `toggleCustom(id, order)` counts only accounts present (refuses unchecking the last present one) and prunes stale ids; `chooseDisplay(custom)` re-checks every present account when none of the checked ones is present; new `forgetAccount(id)` (called after an account is deleted in `account_form.dart`) removes it from Perso and Un compte, and falls back to Tout if Perso is left empty. 3 new widget tests (refuse last present after removal; all-checked removed then Perso re-checks present; forgetAccount).
2. `_chooseGroup` no longer uses `currentContext!` (returns quietly if the chip is not laid out). Chooser look unchanged.
Results: analyze clean; non-golden and golden suites green (see reply).
