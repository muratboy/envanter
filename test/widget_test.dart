import 'package:envanter/core/strings.dart';
import 'package:envanter/data/node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Node', () {
    Node sample({String name = 'Mutfak', NodeKind kind = NodeKind.container}) {
      final now = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      return Node(
        id: 'n1',
        parentId: null,
        kind: kind,
        name: name,
        color: 0xFF3F6C8C,
        sortIndex: 0,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('adı boş olan eşyanın adı yok sayılır', () {
      final item = sample(name: '  ', kind: NodeKind.item);
      expect(item.hasName, isFalse);
      expect(item.trimmedName, isEmpty);
      // "Adsız" etiketini dile duyarlı olsun diye store koyuyor.
      expect(sample(name: ' Mutfak ').trimmedName, 'Mutfak');
    });

    test('toMap/fromMap gidiş dönüşü alanları korur', () {
      final original = sample().copyWith(
        imagePath: 'images/a.jpg',
        lat: 41.0,
        lng: 29.0,
        locationLabel: 'Ev',
        inDrawer: true,
      );
      final restored = Node.fromMap(original.toMap());

      expect(restored.id, original.id);
      expect(restored.kind, original.kind);
      expect(restored.imagePath, 'images/a.jpg');
      expect(restored.lat, 41.0);
      expect(restored.locationLabel, 'Ev');
      expect(restored.inDrawer, isTrue);
      expect(restored.hasGeo, isTrue);
    });

    test('kayıp bilgisi gidiş dönüşte korunur, clearLost temizler', () {
      final lost = sample(kind: NodeKind.item)
          .copyWith(lostAt: DateTime.fromMillisecondsSinceEpoch(1700000001000), lostFrom: 'mutfak');
      final back = Node.fromMap(lost.toMap());
      expect(back.isLost, isTrue);
      expect(back.lostFrom, 'mutfak');
      expect(back.copyWith(clearLost: true).isLost, isFalse);
    });

    test('adet gidiş dönüşte korunur; 0 geçerli, clearQuantity adet tutmayı bırakır', () {
      final counted = sample(kind: NodeKind.item).copyWith(quantity: 0);
      expect(counted.tracksQuantity, isTrue);
      expect(Node.fromMap(counted.toMap()).quantity, 0);
      expect(counted.copyWith(clearQuantity: true).tracksQuantity, isFalse);
      expect(Node.fromMap(sample().toMap()).quantity, isNull);
    });

    test('seçilen simge gidiş dönüşte korunur, clearIcon temizler', () {
      final withIcon = sample().copyWith(icon: 'kitchen');
      expect(Node.fromMap(withIcon.toMap()).icon, 'kitchen');
      expect(withIcon.copyWith(clearIcon: true).icon, isNull);
    });

    test('clearGeo konumu tümüyle temizler', () {
      final cleared = sample().copyWith(lat: 1, lng: 2, locationLabel: 'x').copyWith(clearGeo: true);
      expect(cleared.hasGeo, isFalse);
      expect(cleared.locationLabel, isNull);
    });
  });

  test('Türkçe iyelik eki ünlü uyumuna uyar', () {
    const cases = {
      'Ayşe': "Ayşe'nin",
      'Ali': "Ali'nin",
      'Burak': "Burak'ın",
      'Nur': "Nur'un",
      'Ömür': "Ömür'ün",
      'Mehmet': "Mehmet'in",
      'Aslı': "Aslı'nın",
      'Doğu': "Doğu'nun",
      'Ülkü': "Ülkü'nün",
      'IŞIK': "IŞIK'ın",
    };
    cases.forEach((name, expected) => expect(TrStrings.possessive(name), expected, reason: name));
  });

  test('Türkçe bulunma eki ünlü uyumuna ve sert ünsüze uyar', () {
    const cases = {
      'Ayşe': "Ayşe'de",
      'Ali': "Ali'de",
      'Ahmet': "Ahmet'te",
      'Murat': "Murat'ta",
      'Pınar': "Pınar'da",
      'Oğuz': "Oğuz'da",
      'Burak': "Burak'ta",
      'Elif': "Elif'te",
      'Can': "Can'da",
      'Ömür': "Ömür'de",
      'Nur': "Nur'da",
      'IŞIK': "IŞIK'ta",
    };
    cases.forEach((name, expected) => expect(TrStrings.locative(name), expected, reason: name));
    expect(TrStrings().heldAt('Ahmet'), "Ahmet'te");
    expect(TrStrings().borrowedToStamp('Murat'), "Murat'ta");
  });
}
