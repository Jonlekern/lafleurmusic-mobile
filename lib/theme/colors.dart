import 'package:flutter/material.dart';

/// Couleurs LAFLEURSTUDIO. Une instance par mode ; on les lit avec `context.colors`.
@immutable
class LafleurColors extends ThemeExtension<LafleurColors> {
  const LafleurColors({
    required this.bg,
    required this.bar,
    required this.panel,
    required this.line,
    required this.text,
    required this.sub,
    required this.pink,
    required this.ink,
    required this.onPink,
    required this.onPinkBlack,
    required this.hairline,
    required this.coverBack,
    required this.shadow,
    required this.scrim,
    required this.toastShade,
    required this.thumb,
    required this.textBright,
    required this.textBody,
    required this.textLabel,
    required this.textMuted,
    required this.textDim,
    required this.textDimmer,
    required this.textFaint,
    required this.textHighlight,
    required this.outlineDim,
    required this.border,
    required this.borderSoft,
    required this.divider,
    required this.trackBar,
    required this.raised,
    required this.sheet,
    required this.dialog,
    required this.field,
    required this.inputFill,
    required this.rowHover,
    required this.rule,
    required this.ruleTop,
    required this.pinkTint,
    required this.pinkWash,
    required this.coverGradTop,
    required this.coverGradBottom,
    required this.shine,
    required this.shineFade,
    required this.danger,
    required this.ok,
    required this.jellyfin,
    required this.plex,
  });

  /// Fond de l'écran.
  final Color bg;

  /// Barres (haut, bas, lecteur).
  final Color bar;

  /// Panneaux et cartes.
  final Color panel;

  /// Traits fins.
  final Color line;

  /// Texte principal.
  final Color text;

  /// Texte secondaire.
  final Color sub;

  /// Rose LAFLEURSTUDIO, identique dans les deux modes.
  final Color pink;

  /// Texte posé sur le rose (historique).
  final Color ink;

  /// Texte et icônes sur un fond rose.
  final Color onPink;

  /// Icône ou texte noir sur le rose (filtres).
  final Color onPinkBlack;

  /// Filet qui sépare deux barres.
  final Color hairline;

  /// Fond derrière une pochette.
  final Color coverBack;

  /// Ombre portée.
  final Color shadow;

  /// Voile derrière une feuille ou un menu.
  final Color scrim;

  /// Ombre de la pastille de file.
  final Color toastShade;

  /// Pouce des curseurs et interrupteurs.
  final Color thumb;

  /// Texte très clair.
  final Color textBright;

  /// Texte de corps.
  final Color textBody;

  /// Libellés et sous-titres.
  final Color textLabel;

  /// Texte atténué.
  final Color textMuted;

  /// Texte grisé.
  final Color textDim;

  /// Texte très grisé.
  final Color textDimmer;

  /// Texte presque éteint, icônes inactives.
  final Color textFaint;

  /// Texte clair mis en avant.
  final Color textHighlight;

  /// Contour ou icône inactive.
  final Color outlineDim;

  /// Bordure de bouton ou de champ.
  final Color border;

  /// Bordure de feuille et de dialogue.
  final Color borderSoft;

  /// Séparateur, fond de barre de progression.
  final Color divider;

  /// Rail du curseur de lecture.
  final Color trackBar;

  /// Surface en relief (pastille, rail).
  final Color raised;

  /// Fond des feuilles et menus.
  final Color sheet;

  /// Fond des dialogues.
  final Color dialog;

  /// Fond des champs et cartes de compte.
  final Color field;

  /// Fond du champ de recherche.
  final Color inputFill;

  /// Ligne survolée du menu.
  final Color rowHover;

  /// Filet de liste.
  final Color rule;

  /// Filet au-dessus de la carte de lecture.
  final Color ruleTop;

  /// Dégradé rose sombre.
  final Color pinkTint;

  /// Fond rosé.
  final Color pinkWash;

  /// Haut du fond du cover flow.
  final Color coverGradTop;

  /// Bas du fond du cover flow.
  final Color coverGradBottom;

  /// Reflet de pochette, début.
  final Color shine;

  /// Reflet de pochette, fin.
  final Color shineFade;

  /// Erreur, suppression.
  final Color danger;

  /// Succès, connecté.
  final Color ok;

  /// Couleur de la marque Jellyfin.
  final Color jellyfin;

  /// Couleur de la marque Plex.
  final Color plex;

  /// Mode sombre : les valeurs d'origine.
  static const dark = LafleurColors(
    bg: Color(0xFF0D0D0D),
    bar: Color(0xFF1C1C1C),
    panel: Color(0xFF141414),
    line: Color(0xFF282828),
    text: Color(0xFFFFFFFF),
    sub: Color(0xFF969696),
    pink: Color(0xFFF26EF2),
    ink: Color(0xFF1F1F1F),
    onPink: Color(0xFF111111),
    onPinkBlack: Color(0xFF000000),
    hairline: Color(0xFF000000),
    coverBack: Color(0xFF000000),
    shadow: Color(0xFF000000),
    scrim: Color.from(alpha: 0.5, red: 0, green: 0, blue: 0),
    toastShade: Color(0x99000000),
    thumb: Color(0xFFFFFFFF),
    textBright: Color(0xFFDDDDDD),
    textBody: Color(0xFFCCCCCC),
    textLabel: Color(0xFFBBBBBB),
    textMuted: Color(0xFF999999),
    textDim: Color(0xFF888888),
    textDimmer: Color(0xFF777777),
    textFaint: Color(0xFF666666),
    textHighlight: Color(0xFFF2F2F2),
    outlineDim: Color(0xFF555555),
    border: Color(0xFF444444),
    borderSoft: Color(0xFF3A3A3A),
    divider: Color(0xFF333333),
    trackBar: Color(0xFF3D3D3D),
    raised: Color(0xFF2A2A2A),
    sheet: Color(0xFF232323),
    dialog: Color(0xFF1F1F1F),
    field: Color(0xFF161616),
    inputFill: Color(0xFF0F0F0F),
    rowHover: Color(0xFF262626),
    rule: Color(0xFF1E1E1E),
    ruleTop: Color(0xFF222222),
    pinkTint: Color(0xFF3A2240),
    pinkWash: Color(0xFF2A1A2A),
    coverGradTop: Color(0xFF1D1D1D),
    coverGradBottom: Color(0xFF050505),
    shine: Color(0x47FFFFFF),
    shineFade: Color(0x00FFFFFF),
    danger: Color(0xFFFF6B6B),
    ok: Color(0xFF5FD16F),
    jellyfin: Color(0xFF7AA7FF),
    plex: Color(0xFFE5A00D),
  );

  @override
  LafleurColors copyWith({
    Color? bg,
    Color? bar,
    Color? panel,
    Color? line,
    Color? text,
    Color? sub,
    Color? pink,
    Color? ink,
    Color? onPink,
    Color? onPinkBlack,
    Color? hairline,
    Color? coverBack,
    Color? shadow,
    Color? scrim,
    Color? toastShade,
    Color? thumb,
    Color? textBright,
    Color? textBody,
    Color? textLabel,
    Color? textMuted,
    Color? textDim,
    Color? textDimmer,
    Color? textFaint,
    Color? textHighlight,
    Color? outlineDim,
    Color? border,
    Color? borderSoft,
    Color? divider,
    Color? trackBar,
    Color? raised,
    Color? sheet,
    Color? dialog,
    Color? field,
    Color? inputFill,
    Color? rowHover,
    Color? rule,
    Color? ruleTop,
    Color? pinkTint,
    Color? pinkWash,
    Color? coverGradTop,
    Color? coverGradBottom,
    Color? shine,
    Color? shineFade,
    Color? danger,
    Color? ok,
    Color? jellyfin,
    Color? plex,
  }) {
    return LafleurColors(
      bg: bg ?? this.bg,
      bar: bar ?? this.bar,
      panel: panel ?? this.panel,
      line: line ?? this.line,
      text: text ?? this.text,
      sub: sub ?? this.sub,
      pink: pink ?? this.pink,
      ink: ink ?? this.ink,
      onPink: onPink ?? this.onPink,
      onPinkBlack: onPinkBlack ?? this.onPinkBlack,
      hairline: hairline ?? this.hairline,
      coverBack: coverBack ?? this.coverBack,
      shadow: shadow ?? this.shadow,
      scrim: scrim ?? this.scrim,
      toastShade: toastShade ?? this.toastShade,
      thumb: thumb ?? this.thumb,
      textBright: textBright ?? this.textBright,
      textBody: textBody ?? this.textBody,
      textLabel: textLabel ?? this.textLabel,
      textMuted: textMuted ?? this.textMuted,
      textDim: textDim ?? this.textDim,
      textDimmer: textDimmer ?? this.textDimmer,
      textFaint: textFaint ?? this.textFaint,
      textHighlight: textHighlight ?? this.textHighlight,
      outlineDim: outlineDim ?? this.outlineDim,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      divider: divider ?? this.divider,
      trackBar: trackBar ?? this.trackBar,
      raised: raised ?? this.raised,
      sheet: sheet ?? this.sheet,
      dialog: dialog ?? this.dialog,
      field: field ?? this.field,
      inputFill: inputFill ?? this.inputFill,
      rowHover: rowHover ?? this.rowHover,
      rule: rule ?? this.rule,
      ruleTop: ruleTop ?? this.ruleTop,
      pinkTint: pinkTint ?? this.pinkTint,
      pinkWash: pinkWash ?? this.pinkWash,
      coverGradTop: coverGradTop ?? this.coverGradTop,
      coverGradBottom: coverGradBottom ?? this.coverGradBottom,
      shine: shine ?? this.shine,
      shineFade: shineFade ?? this.shineFade,
      danger: danger ?? this.danger,
      ok: ok ?? this.ok,
      jellyfin: jellyfin ?? this.jellyfin,
      plex: plex ?? this.plex,
    );
  }

  @override
  LafleurColors lerp(ThemeExtension<LafleurColors>? other, double t) {
    if (other is! LafleurColors) return this;
    return LafleurColors(
      bg: Color.lerp(bg, other.bg, t)!,
      bar: Color.lerp(bar, other.bar, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      sub: Color.lerp(sub, other.sub, t)!,
      pink: Color.lerp(pink, other.pink, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      onPink: Color.lerp(onPink, other.onPink, t)!,
      onPinkBlack: Color.lerp(onPinkBlack, other.onPinkBlack, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      coverBack: Color.lerp(coverBack, other.coverBack, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      toastShade: Color.lerp(toastShade, other.toastShade, t)!,
      thumb: Color.lerp(thumb, other.thumb, t)!,
      textBright: Color.lerp(textBright, other.textBright, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textLabel: Color.lerp(textLabel, other.textLabel, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textDim: Color.lerp(textDim, other.textDim, t)!,
      textDimmer: Color.lerp(textDimmer, other.textDimmer, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      textHighlight: Color.lerp(textHighlight, other.textHighlight, t)!,
      outlineDim: Color.lerp(outlineDim, other.outlineDim, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      trackBar: Color.lerp(trackBar, other.trackBar, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      sheet: Color.lerp(sheet, other.sheet, t)!,
      dialog: Color.lerp(dialog, other.dialog, t)!,
      field: Color.lerp(field, other.field, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      rowHover: Color.lerp(rowHover, other.rowHover, t)!,
      rule: Color.lerp(rule, other.rule, t)!,
      ruleTop: Color.lerp(ruleTop, other.ruleTop, t)!,
      pinkTint: Color.lerp(pinkTint, other.pinkTint, t)!,
      pinkWash: Color.lerp(pinkWash, other.pinkWash, t)!,
      coverGradTop: Color.lerp(coverGradTop, other.coverGradTop, t)!,
      coverGradBottom: Color.lerp(coverGradBottom, other.coverGradBottom, t)!,
      shine: Color.lerp(shine, other.shine, t)!,
      shineFade: Color.lerp(shineFade, other.shineFade, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      ok: Color.lerp(ok, other.ok, t)!,
      jellyfin: Color.lerp(jellyfin, other.jellyfin, t)!,
      plex: Color.lerp(plex, other.plex, t)!,
    );
  }
}

extension LafleurColorsX on BuildContext {
  /// Les couleurs du mode courant ; le sombre si le thème n'en porte pas.
  LafleurColors get colors =>
      Theme.of(this).extension<LafleurColors>() ?? LafleurColors.dark;
}
