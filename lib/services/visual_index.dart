import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../data/node.dart';

/// Görüntüyle arama.
///
/// Kayıtlı her resimden küçük bir "renk düzeni" ızgarası çıkarılır (şablon).
/// Arama fotoğrafında bu şablon, farklı boyut ve konumlardaki pencerelerde
/// aranır; çünkü elde çekilen fotoğrafta eşya karenin yalnızca bir kısmını
/// kaplar, etrafında masa, duvar vb. olur. Karşılaştırma sıfır ortalamalı
/// normalize korelasyonla (ZNCC) yapılır: ışık ve kontrast farkından
/// etkilenmez.
///
/// Model yok, ağ yok; tamamen cihaz üstünde. Aynı nesnenin benzer yönden
/// çekilmiş fotoğraflarında iyi çalışır; çok farklı açılar, eşyanın büyük
/// kısmının örtülmesi ya da neredeyse aynı görünen iki eşya onu yanıltır.

/// Bu skorun altı "eşleşme değil". Yanlış yönlendirmektense "bulamadım"
/// demeyi tercih ediyoruz; değer gerçek fotoğraflarla ayarlandı
/// (test/fixtures/visual).
const double kVisualMatchThreshold = 0.75;

/// Görüntüyle aramanın tek bir sonucu.
class VisualMatch {
  const VisualMatch({required this.node, required this.score});
  final Node node;

  /// 0-1 arası benzerlik; eşiğin üstündekiler gösteriliyor.
  final double score;
}

/// Ağırlıklar: parlaklık düzeni en ayırt edici, iki renk kanalı destekleyici.
const List<double> _channelWeights = [0.5, 0.25, 0.25];

/// Düz (dokusuz) bir bölgenin korelasyonu anlamsızdır; bu standart
/// sapmanın altındaki kanallar hesaba katılmaz.
const List<double> _minStd = [6, 3, 3];

/// Izgaradaki yaklaşık hücre sayısı.
const int _targetCells = 192;

/// Kayıtlı bir resmin parmak izi: resmin tamamından ve ortasından alınmış
/// iki şablon. İkincisi, kayıtlı fotoğrafta eşyanın etrafında boşluk
/// kaldığı durumlar için.
class ImageSignature {
  const ImageSignature(this.templates);

  final List<GridTemplate> templates;

  static const _version = 'v3';

  String encode() => [_version, for (final t in templates) t.encode()].join(';');

  static ImageSignature? decode(String? text) {
    if (text == null || !text.startsWith('$_version;')) return null;
    final parts = text.split(';').skip(1);
    final templates = <GridTemplate>[];
    for (final p in parts) {
      final t = GridTemplate.decode(p);
      if (t == null) return null;
      templates.add(t);
    }
    return templates.isEmpty ? null : ImageSignature(templates);
  }
}

/// Karşı renk uzayında (parlaklık, kırmızı-yeşil, sarı-mavi) w×h ızgara.
class GridTemplate {
  GridTemplate(this.w, this.h, this.values);

  final int w;
  final int h;

  /// Kanal kanal sıralı: [kanal0 hücreleri..., kanal1..., kanal2...].
  final Uint8List values;

  double get aspect => w / h;

  String encode() => '$w,$h,${base64Encode(values)}';

  static GridTemplate? decode(String text) {
    final parts = text.split(',');
    if (parts.length != 3) return null;
    final w = int.tryParse(parts[0]);
    final h = int.tryParse(parts[1]);
    if (w == null || h == null || w < 2 || h < 2) return null;
    try {
      final values = base64Decode(parts[2]);
      if (values.length != w * h * 3) return null;
      return GridTemplate(w, h, values);
    } on FormatException {
      return null;
    }
  }

  /// Korelasyon için kanal başına sıfır ortalamalı, birim varyanslı hali.
  /// Düz kanallar null döner.
  List<Float64List?> normalized() {
    final n = w * h;
    return List.generate(3, (c) {
      var sum = 0.0;
      var sq = 0.0;
      for (var i = 0; i < n; i++) {
        final v = values[c * n + i].toDouble();
        sum += v;
        sq += v * v;
      }
      final mean = sum / n;
      final std = math.sqrt(math.max(0, sq / n - mean * mean));
      if (std < _minStd[c]) return null;
      final out = Float64List(n);
      for (var i = 0; i < n; i++) {
        out[i] = (values[c * n + i] - mean) / std;
      }
      return out;
    });
  }
}

/// Karşı renk kanalları; 0-255 aralığına sığacak şekilde ölçekli.
void _opponent(int r, int g, int b, List<double> out) {
  out[0] = (r + g + b) / 3.0;
  out[1] = (r - g) / 2.0 + 127.5;
  out[2] = (r + g - 2 * b) / 4.0 + 127.5;
}

/// Kanal başına toplam alan tablosu; herhangi bir dikdörtgenin ortalaması
/// sabit sürede bulunur.
class _Integral {
  _Integral(img.Image image)
      : width = image.width,
        height = image.height,
        _tables = List.generate(
          3,
          (_) => Float64List((image.width + 1) * (image.height + 1)),
        ) {
    final bytes = image.getBytes(order: img.ChannelOrder.rgb);
    final stride = width + 1;
    final px = [0.0, 0.0, 0.0];
    for (var y = 0; y < height; y++) {
      final rowSums = [0.0, 0.0, 0.0];
      for (var x = 0; x < width; x++) {
        final o = (y * width + x) * 3;
        _opponent(bytes[o], bytes[o + 1], bytes[o + 2], px);
        for (var c = 0; c < 3; c++) {
          rowSums[c] += px[c];
          _tables[c][(y + 1) * stride + x + 1] = _tables[c][y * stride + x + 1] + rowSums[c];
        }
      }
    }
  }

  final int width;
  final int height;
  final List<Float64List> _tables;

  double mean(int c, int x0, int y0, int x1, int y1) {
    final t = _tables[c];
    final s = width + 1;
    final sum = t[y1 * s + x1] - t[y0 * s + x1] - t[y1 * s + x0] + t[y0 * s + x0];
    return sum / ((x1 - x0) * (y1 - y0));
  }
}

img.Image? _decode(Uint8List bytes, int longest) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  return _fit(decoded, longest);
}

img.Image _fit(img.Image decoded, int longest) {
  // Telefon fotoğraflarında yön çoğu zaman EXIF'te; piksellere uygula.
  final upright = img.bakeOrientation(decoded);
  final scale = longest / math.max(upright.width, upright.height);
  if (scale >= 1) return upright;
  return img.copyResize(
    upright,
    width: (upright.width * scale).round(),
    height: (upright.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
}

/// Verilen en-boy oranına uygun, yaklaşık [_targetCells] hücreli ızgara.
(int, int) _gridFor(double aspect) {
  final w = math.max(3, math.sqrt(_targetCells * aspect).round());
  final h = math.max(3, (_targetCells / w).round());
  return (w, h);
}

GridTemplate _templateFrom(_Integral integral, int x0, int y0, int x1, int y1) {
  final (gw, gh) = _gridFor((x1 - x0) / (y1 - y0));
  final n = gw * gh;
  final values = Uint8List(n * 3);
  for (var j = 0; j < gh; j++) {
    final cy0 = y0 + ((y1 - y0) * j / gh).round();
    final cy1 = math.max(cy0 + 1, y0 + ((y1 - y0) * (j + 1) / gh).round());
    for (var i = 0; i < gw; i++) {
      final cx0 = x0 + ((x1 - x0) * i / gw).round();
      final cx1 = math.max(cx0 + 1, x0 + ((x1 - x0) * (i + 1) / gw).round());
      for (var c = 0; c < 3; c++) {
        values[c * n + j * gw + i] = integral.mean(c, cx0, cy0, cx1, cy1).round().clamp(0, 255);
      }
    }
  }
  return GridTemplate(gw, gh, values);
}

/// Bir pencerenin şablonla ZNCC benzerliği; 0-1 aralığına kırpılmış.
double _scoreWindow(
  _Integral q,
  GridTemplate t,
  List<Float64List?> tn,
  int x,
  int y,
  int ww,
  int wh,
  Int32List xs,
  Int32List ys,
) {
  for (var i = 0; i <= t.w; i++) {
    xs[i] = x + (ww * i / t.w).round();
  }
  for (var j = 0; j <= t.h; j++) {
    ys[j] = y + (wh * j / t.h).round();
  }
  final n = t.w * t.h;
  var total = 0.0;
  var weightSum = 0.0;
  for (var c = 0; c < 3; c++) {
    final tc = tn[c];
    if (tc == null) continue;
    var sum = 0.0;
    var sq = 0.0;
    var dot = 0.0;
    var k = 0;
    for (var j = 0; j < t.h; j++) {
      final y0 = ys[j];
      final y1 = math.max(y0 + 1, ys[j + 1]);
      for (var i = 0; i < t.w; i++) {
        final x0 = xs[i];
        final x1 = math.max(x0 + 1, xs[i + 1]);
        final v = q.mean(c, x0, y0, x1, y1);
        sum += v;
        sq += v * v;
        dot += tc[k++] * v;
      }
    }
    final mean = sum / n;
    final std = math.sqrt(math.max(0, sq / n - mean * mean));
    final w = _channelWeights[c];
    weightSum += w;
    // Pencere bu kanalda düzse, dokulu bir şablonla eşleşemez.
    if (std >= _minStd[c]) total += w * (dot / (n * std));
  }
  if (weightSum == 0) return 0;
  return (total / weightSum).clamp(0.0, 1.0);
}

/// İnce şablonun 2×2 bloklarının ortalaması: kaba tarama için ~4 kat ucuz.
GridTemplate _coarsen(GridTemplate t) {
  final cw = (t.w + 1) ~/ 2;
  final ch = (t.h + 1) ~/ 2;
  final n = t.w * t.h;
  final cn = cw * ch;
  final values = Uint8List(cn * 3);
  for (var c = 0; c < 3; c++) {
    for (var j = 0; j < ch; j++) {
      for (var i = 0; i < cw; i++) {
        var sum = 0;
        var count = 0;
        for (var dy = 0; dy < 2; dy++) {
          for (var dx = 0; dx < 2; dx++) {
            final x = i * 2 + dx;
            final y = j * 2 + dy;
            if (x >= t.w || y >= t.h) continue;
            sum += t.values[c * n + y * t.w + x];
            count++;
          }
        }
        values[c * cn + j * cw + i] = (sum / count).round();
      }
    }
  }
  return GridTemplate(cw, ch, values);
}

/// Aday pencere.
class _Window {
  const _Window(this.x, this.y, this.w, this.h, this.score);
  final int x;
  final int y;
  final int w;
  final int h;
  final double score;
}

/// Sorgu fotoğrafında şablonu arayıp en iyi skoru döner. İki aşamalı:
/// kaba ızgarayla bütün pencereler taranır, en iyi birkaç aday ince
/// ızgarayla ve komşu konum/boyutlarla yeniden ölçülür.
double _bestMatch(_Integral q, GridTemplate t) {
  final fine = t.normalized();
  if (fine.every((c) => c == null)) return 0; // tamamen düz resim: anlamsız
  final coarseT = _coarsen(t);
  final coarse = coarseT.normalized();
  final cxs = Int32List(coarseT.w + 1);
  final cys = Int32List(coarseT.h + 1);

  const keep = 10;
  final candidates = <_Window>[];
  void offer(_Window w) {
    if (candidates.length < keep) {
      candidates.add(w);
      return;
    }
    var worst = 0;
    for (var i = 1; i < candidates.length; i++) {
      if (candidates[i].score < candidates[worst].score) worst = i;
    }
    if (w.score > candidates[worst].score) candidates[worst] = w;
  }

  // Perspektif en-boy oranını biraz bozar; birkaç oran deneniyor.
  for (final stretch in const [0.85, 1.0, 1.18]) {
    final aspect = t.aspect * stretch;
    final maxW = math.min(q.width.toDouble(), q.height * aspect);
    for (final s in const [1.0, 0.82, 0.68, 0.56, 0.46, 0.38, 0.31]) {
      final ww = (maxW * s).round();
      final wh = (ww / aspect).round();
      if (ww < t.w * 2 || wh < t.h * 2 || ww > q.width || wh > q.height) continue;
      final step = math.max(2, (math.min(ww, wh) * 0.1).round());
      for (var y = 0; y + wh <= q.height; y += step) {
        for (var x = 0; x + ww <= q.width; x += step) {
          final score = _scoreWindow(q, coarseT, coarse, x, y, ww, wh, cxs, cys);
          offer(_Window(x, y, ww, wh, score));
        }
      }
    }
  }

  final xs = Int32List(t.w + 1);
  final ys = Int32List(t.h + 1);
  var best = 0.0;
  for (final c in candidates) {
    final half = math.max(1, (math.min(c.w, c.h) * 0.05).round());
    for (final scale in const [0.94, 1.0, 1.06]) {
      final ww = (c.w * scale).round();
      final wh = (c.h * scale).round();
      if (ww > q.width || wh > q.height) continue;
      // Ölçek değişince pencereyi merkezinden büyüt/küçült.
      final baseX = c.x + (c.w - ww) ~/ 2;
      final baseY = c.y + (c.h - wh) ~/ 2;
      for (final dy in [-half, 0, half]) {
        for (final dx in [-half, 0, half]) {
          final x = (baseX + dx).clamp(0, q.width - ww);
          final y = (baseY + dy).clamp(0, q.height - wh);
          final score = _scoreWindow(q, t, fine, x, y, ww, wh, xs, ys);
          if (score > best) best = score;
        }
      }
    }
  }
  return best;
}

class VisualIndex {
  /// Kayıtlı resimler bu çözünürlükte işlenir.
  static const int _storedSide = 256;

  /// Arama fotoğrafı biraz daha büyük tutulur: eşya karenin küçük bir
  /// kısmı olabilir.
  static const int _querySide = 256;

  /// Kayıtlı bir resmin parmak izi (arayüzü bekletmemek için isolate'te).
  static Future<ImageSignature?> signatureOf(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return await Isolate.run(() => signatureOfBytes(bytes));
    } on Exception {
      return null;
    }
  }

  @visibleForTesting
  static ImageSignature? signatureOfBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    return decoded == null ? null : signatureOfImage(decoded);
  }

  /// Çözülmüş resmin parmak izi ([signatureOfBytes]'ın çözümden sonraki kısmı; seri ekleme tonla
  /// birlikte tek çözümle hesaplar).
  static ImageSignature signatureOfImage(img.Image decoded) {
    final image = _fit(decoded, _storedSide);
    final integral = _Integral(image);
    final w = image.width;
    final h = image.height;
    // Tamamı ve ortadaki %70'lik kısım.
    final mx = (w * 0.15).round();
    final my = (h * 0.15).round();
    return ImageSignature([
      _templateFrom(integral, 0, 0, w, h),
      _templateFrom(integral, mx, my, w - mx, h - my),
    ]);
  }

  /// Arama fotoğrafını kayıtlı parmak izleriyle karşılaştırır; kimlik ->
  /// skor. Ağır iş olduğu için isolate'te çalışır.
  static Future<Map<String, double>> rank(
    File query,
    Map<String, ImageSignature> stored,
  ) async {
    final bytes = await query.readAsBytes();
    final encoded = {for (final e in stored.entries) e.key: e.value.encode()};
    return Isolate.run(() => rankBytes(bytes, encoded));
  }

  @visibleForTesting
  static Map<String, double> rankBytes(Uint8List queryBytes, Map<String, String> stored) {
    final image = _decode(queryBytes, _querySide);
    if (image == null) return const {};
    final q = _Integral(image);
    final out = <String, double>{};
    for (final e in stored.entries) {
      final sig = ImageSignature.decode(e.value);
      if (sig == null) continue;
      var best = 0.0;
      for (final t in sig.templates) {
        best = math.max(best, _bestMatch(q, t));
      }
      out[e.key] = best;
    }
    return out;
  }
}
