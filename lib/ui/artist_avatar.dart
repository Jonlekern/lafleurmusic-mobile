import 'package:flutter/material.dart';

/// Pastille ronde d'un artiste : la fleur LAFLEUR (pas de photos d'artistes sur le téléphone).
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({super.key, required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: Image.asset(
      'assets/fleur-tile.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    ),
  );
}
