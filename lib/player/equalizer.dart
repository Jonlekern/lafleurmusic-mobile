/// Égaliseur 10 bandes (±12 dB) avec préréglages ; « custom » = Mon réglage.
class Equalizer {
  const Equalizer({
    this.enabled = false,
    required this.gains,
    this.preset = 'flat',
  });

  final bool enabled;
  final List<double> gains;
  final String preset;

  static const bands = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
  static const maxDb = 12.0;

  static const presets = <String, List<double>>{
    'flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'bass': [6, 5, 4, 2, 0, 0, 0, 0, 0, 0],
    'vocal': [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1],
    'rock': [4, 3, 1, -1, -1, 1, 3, 4, 4, 4],
    'electro': [5, 4, 1, 0, -2, 1, 0, 2, 4, 5],
  };

  static Equalizer named(String name) => Equalizer(
    gains: List.of(presets[name] ?? presets['flat']!),
    preset: presets.containsKey(name) ? name : 'flat',
  );

  Equalizer copyWith({bool? enabled, List<double>? gains, String? preset}) =>
      Equalizer(
        enabled: enabled ?? this.enabled,
        gains: gains ?? this.gains,
        preset: preset ?? this.preset,
      );

  Equalizer withGain(int band, double db) {
    final g = List.of(gains);
    g[band] = db.clamp(-maxDb, maxDb);
    return copyWith(gains: g, preset: 'custom');
  }

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'gains': gains,
    'preset': preset,
  };

  static Equalizer fromJson(Map<String, Object?> j) {
    final raw = j['gains'];
    if (raw is! List ||
        raw.length != bands.length ||
        raw.any((v) => v is! num)) {
      return named('flat');
    }
    return Equalizer(
      enabled: j['enabled'] == true,
      gains: [for (final v in raw) (v as num).toDouble().clamp(-maxDb, maxDb)],
      preset: j['preset'] is String ? j['preset']! as String : 'custom',
    );
  }
}
