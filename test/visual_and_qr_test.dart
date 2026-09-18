import 'dart:io';
import 'dart:typed_data';

import 'package:envanter/data/node.dart';
import 'package:envanter/services/qr_service.dart';
import 'package:envanter/services/visual_index.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Node node({required String id, required NodeKind kind, String name = 'Matkap'}) {
  final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
  return Node(
    id: id,
    parentId: null,
    kind: kind,
    name: name,
    color: 0xFF3F6C8C,
    sortIndex: 0,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('QR kodu', () {
    test('üretilen kod geri çözülür', () {
      final container = node(id: 'abc-123', kind: NodeKind.container, name: 'Mutfak');
      final code = QrService.parse(QrService.payloadFor(container));

      expect(code, isNotNull);
      expect(code!.id, 'abc-123');
      expect(code.isContainer, isTrue);
    });

    test('eşya kodu klasörden ayrılır', () {
      final item = node(id: 'xyz-9', kind: NodeKind.item);
      final code = QrService.parse(QrService.payloadFor(item));

      expect(code!.id, 'xyz-9');
      expect(code.isContainer, isFalse);
    });

    test('türkçe karakterli ad kodu bozmaz', () {
      final item = node(id: 'id-1', kind: NodeKind.item, name: 'Şarj aleti / çekmece');
      expect(QrService.parse(QrService.payloadFor(item))!.id, 'id-1');
    });

    test('yabancı kodlar reddedilir', () {
      expect(QrService.parse('https://example.com'), isNull);
      expect(QrService.parse('envanter://baska/1'), isNull);
      expect(QrService.parse('envanter://item/'), isNull);
      expect(QrService.parse('rastgele metin'), isNull);
    });
  });

  group('görüntüyle arama', () {
    // Gerçek fikstürler: emülatörün sanal odasında kamerayla çekilmiş
    // fotoğraflar ve bunlardan türetilmiş zor durumlar. Eşiği bunlar belirledi.
    const dir = 'test/fixtures/visual';
    final stored = {
      for (final name in ['kutu', 'box_recolored', 'house', 'books', 'plant'])
        name: VisualIndex.signatureOfBytes(
          File('$dir/stored_$name.jpg').readAsBytesSync(),
        )!.encode(),
    };
    Map<String, double> rank(String query) =>
        VisualIndex.rankBytes(File('$dir/query_$query.jpg').readAsBytesSync(), stored);

    for (final query in ['kutu_room', 'kutu_preview', 'kutu_perspective', 'kutu_small_rotated']) {
      test('"$query" doğru kutuyu bulur ve ilk sıraya koyar', () {
        final scores = rank(query);
        final best = scores.entries.reduce((a, b) => a.value >= b.value ? a : b);

        expect(best.key, 'kutu');
        expect(scores['kutu'], greaterThanOrEqualTo(kVisualMatchThreshold));
      });
    }

    test('renkleri farklı "ikiz" kutu eşleşme sayılmaz', () {
      for (final query in ['kutu_room', 'kutu_preview', 'kutu_perspective', 'kutu_small_rotated']) {
        expect(rank(query)['box_recolored'], lessThan(kVisualMatchThreshold), reason: query);
      }
    });

    for (final query in ['room_tv', 'wall', 'qr_poster']) {
      test('kayıtlı eşya olmayan "$query" için "bulunamadı"', () {
        final scores = rank(query);
        for (final e in scores.entries) {
          expect(e.value, lessThan(kVisualMatchThreshold), reason: '${e.key}=${e.value}');
        }
      });
    }

    test('düz renkli bir fotoğraf hiçbir şeyle eşleşmez', () {
      final flat = img.Image(width: 200, height: 300);
      img.fill(flat, color: img.ColorRgb8(140, 110, 80));
      final scores = VisualIndex.rankBytes(Uint8List.fromList(img.encodeJpg(flat)), stored);
      expect(scores.values.every((v) => v < kVisualMatchThreshold), isTrue);
    });

    test('parmak izi metne yazılıp aynen geri okunur', () {
      final original = ImageSignature.decode(stored['kutu'])!;
      final again = ImageSignature.decode(original.encode())!;
      expect(again.encode(), original.encode());
      expect(again.templates.length, 2);
    });

    test('eski ya da bozuk parmak izi yok sayılır', () {
      expect(ImageSignature.decode(null), isNull);
      expect(ImageSignature.decode('a3f09c'), isNull); // eski dHash biçimi
      expect(ImageSignature.decode('v3;4,3,bozuk!'), isNull);
      expect(ImageSignature.decode('v3;4,3,AAAA'), isNull); // uzunluk tutmuyor
    });
  });
}
