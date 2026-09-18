import 'package:envanter/data/lots.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/sync/fields.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter_test/flutter_test.dart';

/// Farklı son kullanma tarihli paketler: 6 yoğurdun 2'si 5 Eki, 4'ü 12 Eki.
void main() {
  final today = DateTime(2026, 10, 1);
  DateTime day(int d) => DateTime(2026, 10, d);
  Node yogurt({int? quantity, DateTime? expires, List<Lot> lots = const [], String? shelf, DateTime? bought}) =>
      Node(
        id: 'y',
        parentId: 'dolap',
        kind: NodeKind.item,
        name: 'Yoğurt',
        color: 1,
        sortIndex: 0,
        createdAt: today,
        updatedAt: today,
        quantity: quantity,
        expiresAt: expires,
        lots: lots,
        shelfLife: shelf,
        purchasedAt: bought,
      );

  test('farklı tarihli paket eklenince paket listesi olur; adet toplamdır, en yakın tarih önde', () {
    final n = addLot(yogurt(quantity: 2, expires: day(5)), 4, day(12));
    expect(n.lots, [Lot(2, day(5)), Lot(4, day(12))]);
    expect(n.quantity, 6);
    expect(n.expiresAt, isNull);
    expect(n.effectiveExpiry, day(5));
    expect(n.lastExpiry, day(12));
    expect(n.expiryDates, [day(5), day(12)]);
  });

  test('aynı tarihli paket birleşir; tek tarih kalınca eşya eskisi gibi tek tarihli', () {
    final n = addLot(yogurt(quantity: 2, expires: day(5)), 3, day(5));
    expect(n.lots, isEmpty);
    expect((n.quantity, n.expiresAt), (5, day(5)));
  });

  test('kullanılan en eski paketten gider; o paket bitince sıradakine geçilir', () {
    var n = yogurt(lots: [Lot(2, day(5)), Lot(4, day(12))], quantity: 6);
    n = setQuantityByLots(n, 5, today);
    expect(n.lots, [Lot(1, day(5)), Lot(4, day(12))]);
    n = setQuantityByLots(n, 3, today);
    // 5 Ekim bitti, 12 Ekim'den de bir tane: tek tarih kaldı.
    expect(n.lots, isEmpty);
    expect((n.quantity, n.expiresAt), (3, day(12)));
  });

  test('− tarihi geçmemiş en eski paketten alır; geçmiş olan yalnızca hepsi geçmişse', () {
    // 2'si 28 Eylül'de geçti, 3'ü 5 Ekim'de, 1'i 12 Ekim'de.
    var n = yogurt(lots: [Lot(2, DateTime(2026, 9, 28)), Lot(3, day(5)), Lot(1, day(12))], quantity: 6);
    n = setQuantityByLots(n, 5, today);
    expect(n.lots, [Lot(2, DateTime(2026, 9, 28)), Lot(2, day(5)), Lot(1, day(12))]);
    expect(expiredUnits(n, today), 2, reason: 'bozulmuş olanlar yerinde, atılmayı bekliyor');
    n = setQuantityByLots(n, 2, today);
    expect(n.lots, isEmpty);
    expect((n.quantity, n.expiresAt), (2, DateTime(2026, 9, 28)), reason: 'geçmemiş kalmadı: geçmişten');
    n = setQuantityByLots(n, 1, today);
    expect(n.quantity, 1);
  });

  test('eklenen en yeni pakete girer; raf ömrü varsa bugünün tarihiyle yeni paket olur', () {
    final n = setQuantityByLots(yogurt(lots: [Lot(2, day(5)), Lot(4, day(12))], quantity: 6), 7, today);
    expect(n.lots, [Lot(2, day(5)), Lot(5, day(12))]);

    // Muz: raf ömrü 1 hafta; eldeki 2 tanesi eski tarihli, eklenen bugün alındı.
    final muz = yogurt(quantity: 2, shelf: '1w', bought: DateTime(2026, 9, 28));
    final more = setQuantityByLots(muz, 5, today);
    expect(more.lots, [Lot(2, day(5)), Lot(3, day(8))]);

    // Bitmiş raf ömürlü eşyaya eklenen bugün alınmıştır (eski yazılı tarih kalkar).
    final fresh = setQuantityByLots(yogurt(quantity: 0, shelf: '1w', expires: day(2)), 4, today);
    expect((fresh.quantity, fresh.expiresAt, fresh.purchasedAt), (4, null, today));
    expect(fresh.effectiveExpiry, day(8));
  });

  test('adedi tutulmayan eşyada saymaya başlamak tarihlere dokunmaz; 0 da yazılabilir', () {
    // Raf ömürlü, alış tarihi ve son kullanması yazılı ama sayılmayan yoğurt: "bitmiş" değil.
    final uncounted = yogurt(shelf: '2w', bought: day(1), expires: day(20));
    final counted = setQuantityByLots(uncounted, 2, day(9));
    expect(counted.quantity, 2);
    expect(counted.purchasedAt, day(1), reason: 'alış tarihi bugüne çekilmez');
    expect(counted.expiresAt, day(20), reason: 'yazılı tarih silinmez');
    expect(setQuantityByLots(uncounted, 0, day(9)).quantity, 0, reason: 'sayılmayan eşya tükendi yapılabilir');
    // Gerçekten bitmiş (adet 0) raf ömürlü eşyaya eklenen ise bugün alınmıştır.
    final restocked = setQuantityByLots(yogurt(quantity: 0, shelf: '2w', bought: day(1)), 3, day(9));
    expect(restocked.purchasedAt, day(9));
  });

  test('tarihi geçenler sayılır ve atılır; kalanlar yerinde, hepsi gidince adet 0', () {
    final n = yogurt(lots: [Lot(2, DateTime(2026, 9, 29)), Lot(1, today), Lot(3, day(12))], quantity: 6);
    expect(expiredUnits(n, today), 2, reason: 'son günü bugün olan henüz geçmedi');
    final kept = discardExpired(n, today);
    expect(kept.lots, [Lot(1, today), Lot(3, day(12))]);
    expect(kept.quantity, 4);

    final allGone = discardExpired(yogurt(quantity: 3, expires: DateTime(2026, 9, 20)), today);
    expect(allGone.quantity, 0);
  });

  test('düzenleyicide paketin adedi ve tarihi değişir; + ile eklenenin tarihi taşınır', () {
    var n = yogurt(lots: [Lot(2, day(5)), Lot(4, day(12))], quantity: 6);
    n = setLotCount(n, 1, 1);
    expect(n.lots, [Lot(2, day(5)), Lot(1, day(12))]);
    expect(n.quantity, 3);
    n = redateLot(n, 0, day(20));
    expect(n.lots, [Lot(1, day(12)), Lot(2, day(20))]);
    n = moveUnits(n, 1, day(20), day(25));
    expect(n.lots, [Lot(1, day(12)), Lot(1, day(20)), Lot(1, day(25))]);
    n = setLotCount(n, 0, 0);
    expect(n.lots, [Lot(1, day(20)), Lot(1, day(25))]);
  });

  test('paketler kayda yazılıp okunur; ağdan bozuk gelirse atılır, adet toplamdan', () {
    final n = yogurt(lots: [Lot(2, day(5)), Lot(4, day(12))], quantity: 6);
    expect(Node.fromMap(n.toMap()).lots, n.lots);
    final wire = sanitizeNode({...n.toMap(), 'quantity': 99})!;
    expect(wire.lots, n.lots);
    expect(wire.quantity, 6);
    expect(sanitizeNode({...n.toMap(), 'lots': 'bozuk'})!.lots, isEmpty);
  });

  test('eşitlemede adet ve paketler birlikte birleşir', () {
    final base = stampChanges(null, yogurt(quantity: 2, expires: day(5)), today);
    final t1 = today.add(const Duration(minutes: 1));
    final t2 = today.add(const Duration(minutes: 2));
    // Ayşe farklı tarihli paket ekledi, Ali adı değiştirdi.
    final ayse = stampChanges(base, addLot(base, 4, day(12)).copyWith(updatedAt: t1), t1);
    final ali = stampChanges(base, base.copyWith(name: 'Süzme yoğurt', updatedAt: t2), t2);
    final m = mergeNode(ali, ayse);
    expect((m.name, m.quantity), ('Süzme yoğurt', 6));
    expect(m.lots, [Lot(2, day(5)), Lot(4, day(12))]);
  });
}
