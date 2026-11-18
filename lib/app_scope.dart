import 'package:flutter/widgets.dart';

import 'l10n/strings.dart';
import 'library/covers.dart';
import 'library/db.dart';
import 'player/equalizer.dart';
import 'player/loudness.dart';
import 'player/player.dart';
import 'settings.dart';

/// Les services de l'appli, accessibles depuis tous les écrans.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.db,
    required this.player,
    required this.covers,
    required this.strings,
    ValueNotifier<Equalizer>? equalizer,
    this.artistGrid,
    this.settings,
    this.saveSettings,
    this.loudness,
    required super.child,
  }) : _eq = equalizer;
  final LibraryDb db;
  final PlayerController player;
  final Covers covers;
  final Strings strings;
  final ValueNotifier<Equalizer>? _eq;
  final ValueNotifier<bool>?
  artistGrid; // vue Artistes : grille (sinon liste), retenue
  final AppSettings? settings; // réglages (enregistrés par saveSettings)
  final VoidCallback? saveSettings;
  final LoudnessService? loudness; // Volume égal
  static final _noEq = ValueNotifier(Equalizer.named('flat'));

  /// Réglage d'égaliseur en cours (l'appli l'applique au lecteur et l'enregistre à chaque changement).
  ValueNotifier<Equalizer> get equalizer => _eq ?? _noEq;

  static AppScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => old.strings.fr != strings.fr;
}
