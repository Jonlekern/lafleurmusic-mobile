import 'package:flutter/widgets.dart';

import '../phone/phone_shell.dart';
import 'classic_menu.dart';

/// Mode Classic sur le téléphone (maquette 6 A) : la vue téléphone, avec le menu et la molette
/// ([ClassicMenu]) à la place de l'Accueil. Le reste est celui du mode normal : couché, le Cover
/// Flow ; les écrans ouverts depuis le menu (Cover Flow, En cours, Réglages, Sur mon iPhone) ;
/// le message d'un morceau illisible.
///
/// Couché, « Ouvrir l'album » du Cover Flow ouvre l'album dans le menu, et retour ne quitte
/// l'appli qu'à la racine du menu ([ClassicMenuController]).
class ClassicShell extends StatefulWidget {
  const ClassicShell({super.key, this.debugStart, this.debugScreens});
  final String? debugStart; // voir [PhoneShell.debugStart]
  final List<Widget> Function()? debugScreens; // voir [PhoneShell.debugScreens]

  @override
  State<ClassicShell> createState() => _ClassicShellState();
}

class _ClassicShellState extends State<ClassicShell> {
  final _menu = ClassicMenuController();

  @override
  void dispose() {
    _menu.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PhoneShell(
    debugStart: widget.debugStart,
    debugScreens: widget.debugScreens,
    home: ClassicMenu(controller: _menu),
    onFlowOpen: _menu.openAlbum,
    homeAtRoot: _menu.atRoot,
  );
}
