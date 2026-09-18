import 'package:flutter/material.dart';

/// Kart renkleri: kağıt, klasör ve fiş kartı tonları. Açık zeminli oldukları
/// için yazı üstlerinde koyu mürekkeple durur; son ikisi koyu kartlar.
const List<Color> kCardPalette = <Color>[
  Color(0xFFD9D3C7), // taş
  Color(0xFFB9C7DF), // mürekkep mavisi
  Color(0xFFB4D6E4), // gök
  Color(0xFFB3DBCB), // nane
  Color(0xFFC7D9B2), // adaçayı
  Color(0xFFDDE2A9), // fıstık
  Color(0xFFEBD9A2), // manila
  Color(0xFFF0CBA4), // kayısı
  Color(0xFFE9B6A3), // kiremit
  Color(0xFFEDBCC1), // gül
  Color(0xFFE1BBD4), // orkide
  Color(0xFFCFBFE6), // leylak
  Color(0xFFBFC3EE), // lavanta
  Color(0xFFD7BEA7), // kil
  Color(0xFF8F8B85), // grafit
  Color(0xFF34363D), // gece
];

/// Önceki sürümün doygun renkleri; kayıtlar değiştirilmeden, gösterirken
/// aynı sıradaki yeni renge çevrilir (ortak kullanımda da sorun çıkmaz).
const List<int> _legacyPalette = [
  0xFF5B6B7C, 0xFF3F6C8C, 0xFF2F8FA3, 0xFF2E8B72, 0xFF5A8F3C, 0xFF8A9A2B, //
  0xFFB8912F, 0xFFC67A2E, 0xFFC0552F, 0xFFB03A46, 0xFFA63C6E, 0xFF7D4AA0, //
  0xFF5A54B8, 0xFF7A6250, 0xFF6E6E73, 0xFF2C3440,
];

/// Kayıtlı renk değerinin bugünkü paletteki karşılığı.
Color canonicalCardColor(int stored) {
  final legacy = _legacyPalette.indexOf(stored);
  return legacy >= 0 ? kCardPalette[legacy] : Color(stored);
}

/// Kartın ekranda görünen rengi; koyu temada kağıt tonları biraz kısılır ki
/// karanlıkta göz almasın.
Color cardTone(int stored, Brightness brightness) {
  final base = canonicalCardColor(stored);
  return brightness == Brightness.dark ? Color.lerp(base, const Color(0xFF14120F), 0.12)! : base;
}

/// Kart üzerindeki mürekkep.
const kInk = Color(0xFF1E1B18);

/// Verilen zemin üzerinde okunabilir metin rengi.
Color onColorOf(Color background) =>
    background.computeLuminance() > 0.33 ? kInk : const Color(0xFFF7F3EC);

/// Bir fotoğrafın tonuna en uyumlu kart rengi. Soluk (gri, bej, siyah
/// beyaz) fotoğraflara nötr renkler, canlı fotoğraflara tonu en yakın renk.
Color nearestPaletteColor(Color tone) {
  final hsv = HSVColor.fromColor(tone);
  final neutrals = [kCardPalette[0], kCardPalette[13], kCardPalette[14], kCardPalette[15]];
  if (hsv.saturation < 0.22) {
    return neutrals.reduce((a, b) => _rgbDistance(a, tone) <= _rgbDistance(b, tone) ? a : b);
  }
  double score(Color c) {
    final p = HSVColor.fromColor(c);
    final dh = (p.hue - hsv.hue).abs();
    return (dh > 180 ? 360 - dh : dh) / 180;
  }

  return kCardPalette.where((c) => !neutrals.contains(c)).reduce((a, b) => score(a) <= score(b) ? a : b);
}

double _rgbDistance(Color a, Color b) {
  final dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b;
  return dr * dr + dg * dg + db * db;
}
