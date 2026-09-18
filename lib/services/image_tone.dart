import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import '../core/palette.dart';

/// Fotoğrafın baskın tonu; kartın rengini fotoğrafla uyumlu seçmek için.
abstract final class ImageTone {
  /// Fotoğrafa en uyumlu kart rengi; okunamazsa null.
  static Future<Color?> paletteMatch(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final argb = await compute(dominantTone, bytes);
      return argb == null ? null : nearestPaletteColor(Color(argb));
    } on Object {
      return null;
    }
  }
}

/// Küçültülmüş resimde, doygun ve orta parlaklıktaki piksellere daha çok
/// ağırlık veren ortalama renk (ARGB). Arka plandaki beyaz duvar ya da
/// gölgeler tonu soldurmasın diye.
@visibleForTesting
int? dominantTone(Uint8List bytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object {
    return null; // bozuk dosya
  }
  if (decoded == null) return null;
  return toneOfImage(decoded);
}

/// [dominantTone]'un çözülmüş resimdeki hesabı. Seri eklemede resim bir kez çözülür, ton ve görüntüyle arama
/// izi aynı resimden çıkar: iki kez çözmek sürenin çoğuydu.
int? toneOfImage(img.Image decoded) {
  final small = img.copyResize(decoded, width: 32, height: 32, interpolation: img.Interpolation.average);
  var r = 0.0, g = 0.0, b = 0.0, total = 0.0;
  for (final px in small) {
    final pr = px.r / 255, pg = px.g / 255, pb = px.b / 255;
    final max = [pr, pg, pb].reduce((a, c) => a > c ? a : c);
    final min = [pr, pg, pb].reduce((a, c) => a < c ? a : c);
    final saturation = max == 0 ? 0.0 : (max - min) / max;
    final midtone = 1 - (max - 0.55).abs() * 1.4;
    final w = 0.05 + saturation * saturation * midtone.clamp(0.0, 1.0);
    r += pr * w;
    g += pg * w;
    b += pb * w;
    total += w;
  }
  if (total == 0) return null;
  int ch(double v) => (v / total * 255).round().clamp(0, 255);
  return 0xFF000000 | (ch(r) << 16) | (ch(g) << 8) | ch(b);
}
