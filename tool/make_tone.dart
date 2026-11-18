// Fabrique test/fixtures/tone-20.wav : sinus 1 kHz, amplitude 0,1, stéréo 44,1 kHz, 10 s (≈ −20 LUFS).
// dart run tool/make_tone.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  const rate = 44100, seconds = 10, channels = 2;
  const frames = rate * seconds;
  final data = ByteData(frames * channels * 2);
  for (var i = 0; i < frames; i++) {
    final v = (0.1 * sin(2 * pi * 1000 * i / rate) * 32767).round();
    data.setInt16(i * 4, v, Endian.little);
    data.setInt16(i * 4 + 2, v, Endian.little);
  }
  final h = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      h.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  h.setUint32(4, 36 + data.lengthInBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, channels, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * channels * 2, Endian.little);
  h.setUint16(32, channels * 2, Endian.little);
  h.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  h.setUint32(40, data.lengthInBytes, Endian.little);
  File('test/fixtures/tone-20.wav').writeAsBytesSync([
    ...h.buffer.asUint8List(),
    ...data.buffer.asUint8List(),
  ]);
}
