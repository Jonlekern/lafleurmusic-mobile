import 'package:flutter/foundation.dart';
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

/// L'écran de cet appareil est celui d'une tablette (pour les textes : « iPad », « tablette »).
bool get onTablet {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return false;
  return isTablet(
    view.physicalSize / view.devicePixelRatio,
    defaultTargetPlatform,
  );
}

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

/// [orientationsFor] l'écran de cet appareil.
List<DeviceOrientation> get deviceOrientations {
  final view = WidgetsBinding.instance.platformDispatcher.implicitView;
  if (view == null) return mobileOrientations;
  return orientationsFor(view.physicalSize / view.devicePixelRatio);
}
