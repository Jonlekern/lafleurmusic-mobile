import 'package:flutter/widgets.dart';

import '../phone/phone_shell.dart';
import 'classic_menu.dart';

/// Mode Classic sur le téléphone (maquette 6 A) : la vue téléphone, avec le menu et la molette
/// ([ClassicMenu]) à la place de l'Accueil. Le reste est celui du mode normal : couché, le Cover
/// Flow ; les écrans ouverts depuis le menu (Cover Flow, En cours, Réglages, Sur mon iPhone) ;
/// le message d'un morceau illisible.
class ClassicShell extends StatelessWidget {
  const ClassicShell({super.key, this.debugStart, this.debugScreens});
  final String? debugStart; // voir [PhoneShell.debugStart]
  final List<Widget> Function()? debugScreens; // voir [PhoneShell.debugScreens]

  @override
  Widget build(BuildContext context) => PhoneShell(
    debugStart: debugStart,
    debugScreens: debugScreens,
    home: const ClassicMenu(),
  );
}
