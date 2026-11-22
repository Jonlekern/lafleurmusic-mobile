import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../phone/phone_shell.dart';
import 'click_wheel.dart';

// Maquettes 6 A et 12 A : l'écran sous la barre du haut, la molette dessous
const _screenHeight = 300.0;
const _gap = 34.0; // entre l'écran et la molette
const _top = 14.0; // sous la barre du haut

/// Le cadre du Mode Classic (menu et En cours) : la barre du haut, l'écran façon iPod
/// (300 points de haut) et la molette. Sur un petit téléphone, tout se resserre au même
/// rythme et rien ne déborde.
class ClassicFrame extends StatelessWidget {
  const ClassicFrame({super.key, required this.screen, required this.wheel});
  final Widget screen;

  /// La molette ([ClickWheel], au besoin dans un [PlayerProgress]).
  final Widget wheel;

  /// Hauteur de l'écran sans resserrement.
  static const screenHeight = _screenHeight;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colors.bg,
    body: SafeArea(
      child: Column(
        children: [
          const PhoneHeader(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                // petit téléphone : tout se resserre au même rythme, rien ne déborde
                const ideal = _top + _screenHeight + _gap + ClickWheel.size;
                final k = math.min(1.0, c.maxHeight / (ideal + _top));
                final size = math.min(ClickWheel.size * k, c.maxWidth);
                return Column(
                  children: [
                    SizedBox(height: _top * k),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(height: _screenHeight * k, child: screen),
                    ),
                    SizedBox(height: _gap * k),
                    SizedBox.square(
                      dimension: size,
                      child: FittedBox(child: wheel),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
