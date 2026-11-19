import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android ou iOS.
bool isMobilePlatform(TargetPlatform p) =>
    p == TargetPlatform.android || p == TargetPlatform.iOS;

/// Tablette : Android ou iOS dont le plus petit côté fait au moins 600 px logiques (la règle d'Android).
/// Le plus petit côté, pas la largeur : un iPad debout (768 px) est une tablette, un gros téléphone
/// couché (932 px) n'en est pas une.
bool isTablet(Size size, TargetPlatform platform) =>
    isMobilePlatform(platform) && size.shortestSide >= 600;

bool _tabletMode = false;

/// L'appli est en disposition tablette (pour les textes : « iPad », « tablette »). Posé par [AdaptiveHome]
/// d'après la taille de la fenêtre (MediaQuery), la même qui choisit la disposition : en vue partagée,
/// une fenêtre étroite redevient un téléphone.
bool get onTablet => _tabletMode;
void setTabletMode(bool v) => _tabletMode = v;

/// Orientations du téléphone : debout et couché des deux côtés (le Cover Flow est l'écran couché).
const mobileOrientations = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];
const uprightOnly = [DeviceOrientation.portraitUp];

/// Orientations permises sur un écran de la taille [size] : les quatre sur une tablette.
List<DeviceOrientation> orientationsFor(Size size) =>
    size.shortestSide >= 600 ? DeviceOrientation.values : mobileOrientations;

/// Orientations au lancement, avant le premier écran : d'après la fenêtre de l'appareil. Ensuite
/// [AdaptiveHome] suit la fenêtre (MediaQuery).
List<DeviceOrientation> get launchOrientations {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return mobileOrientations;
  return orientationsFor(view.physicalSize / view.devicePixelRatio);
}
