// Ölçüm: seri eklemede fotoğraf başına hazırlık (kart rengi + görüntüyle arama izi) süresi.
// Adı _test ile bitmediği için test takımına girmez: `flutter test test/bench/burst_bench.dart`
// (sonuç "OLCUM" satırlarında). Hata ayıklama modunda ölçer: sayılar telefondakinden farklıdır,
// asıl anlamlı olan yöntemler arasındaki orandır.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:envanter/services/image_tone.dart';
import 'package:envanter/services/visual_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Bir test fotoğrafı 1800 piksele büyütülür, üstüne doku eklenir (düz büyütülmüş resim JPEG'de
/// gerçek fotoğraftan çok daha az yer tutar, çözmesi de kolaylaşır).
Uint8List photo(File source, int seed) {
  final random = math.Random(seed);
  final base = img.decodeImage(source.readAsBytesSync())!;
  final big = img.copyResize(base, width: 1350, height: 1800, interpolation: img.Interpolation.cubic);
  for (final px in big) {
    final n = random.nextInt(25) - 12;
    px
      ..r = (px.r + n).clamp(0, 255)
      ..g = (px.g + n).clamp(0, 255)
      ..b = (px.b + n).clamp(0, 255);
  }
  return Uint8List.fromList(img.encodeJpg(big, quality: 88));
}

(int?, String?) both(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return (null, null);
  return (toneOfImage(decoded), VisualIndex.signatureOfImage(decoded).encode());
}

Future<(int?, String?)> bothOff(Uint8List bytes) => Isolate.run(() => both(bytes));

Future<void> pool(int workers, List<Future<void> Function()> jobs) async {
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      await jobs[next++]();
    }
  }

  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
}

void main() {
  test('seri ekleme hazırlığı', () async {
    final sources = Directory('test/fixtures/visual').listSync().whereType<File>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final dir = Directory.systemTemp.createTempSync('seri_bench');
    final files = <File>[];
    for (final (i, source) in sources.take(8).indexed) {
      files.add(File('${dir.path}/p$i.jpg')..writeAsBytesSync(photo(source, i)));
    }
    final kb = files.map((f) => f.lengthSync() ~/ 1024).toList();
    // ignore: avoid_print
    print('OLCUM dosyalar ${files.length} adet, ${kb.reduce(math.min)}–${kb.reduce(math.max)} KB, 1350x1800');

    Future<int> ms(Future<void> Function() run) async {
      final watch = Stopwatch()..start();
      await run();
      return watch.elapsedMilliseconds;
    }

    // Isınma (JIT).
    await ImageTone.paletteMatch(files.first);
    await VisualIndex.signatureOf(files.first);

    final decode = await ms(() async {
      for (final f in files) {
        img.decodeImage(f.readAsBytesSync());
      }
    });
    final old = await ms(() async {
      for (final f in files) {
        await ImageTone.paletteMatch(f);
        await VisualIndex.signatureOf(f);
      }
    });
    final once = await ms(() async {
      for (final f in files) {
        await bothOff(await f.readAsBytes());
      }
    });
    final parallel = <int, int>{};
    for (final workers in [2, 3, 4]) {
      parallel[workers] = await ms(() => pool(workers, [for (final f in files) () async => bothOff(await f.readAsBytes())]));
    }
    final n = files.length;
    // ignore: avoid_print
    print('OLCUM fotoğraf başına: yalnızca çözme ${decode ~/ n} ms; eski (iki çözüm, sırayla) ${old ~/ n} ms; '
        'tek çözüm ${once ~/ n} ms; paralel ${[for (final e in parallel.entries) '${e.key}: ${e.value ~/ n} ms'].join(', ')} '
        '(işlemci ${Platform.numberOfProcessors})');
    // Sonuçlar eskisiyle aynı mı (ton ve iz).
    for (final f in files) {
      final bytes = f.readAsBytesSync();
      final (tone, signature) = both(bytes);
      expect(tone, dominantTone(bytes));
      expect(signature, VisualIndex.signatureOfBytes(bytes)!.encode());
    }
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
