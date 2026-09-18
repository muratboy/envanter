import 'package:envanter/data/node.dart';
import 'package:envanter/sync/fields.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter_test/flutter_test.dart';

/// Alan bazında birleştirme: aynı eşyada farklı alanlar değişirse ikisi de kalır.
void main() {
  final t0 = DateTime(2026, 9, 1, 12);
  final base = stampChanges(
    null,
    Node(
      id: 'pil',
      parentId: 'mutfak',
      kind: NodeKind.item,
      name: 'Pil',
      color: 1,
      sortIndex: 0,
      createdAt: t0,
      updatedAt: t0,
      quantity: 4,
      note: 'AA',
    ),
    t0,
  );

  Node edit(Node n, Node Function(Node n) change, DateTime at, String by) =>
      stampChanges(n, change(n).copyWith(updatedBy: by, updatedAt: at), at);

  test('ilk damga bütün grupları yazar; değişiklik yalnızca kendi grubunu ilerletir', () {
    expect(base.allFieldTimes.values.toSet(), {t0.millisecondsSinceEpoch});
    final t1 = t0.add(const Duration(minutes: 5));
    final renamed = edit(base, (n) => n.copyWith(name: 'Kalem pil'), t1, 'ayse');
    expect(renamed.timeOf(NodeField.name), t1.millisecondsSinceEpoch);
    expect(renamed.timeOf(NodeField.quantity), t0.millisecondsSinceEpoch);
    expect(renamed.updatedAt, t1);
  });

  test('Ayşe adedi, Ali adı değiştirdi: ikisi de kalır, sıra fark etmez', () {
    final ayse = edit(base, (n) => n.copyWith(quantity: 2), t0.add(const Duration(minutes: 1)), 'ayse');
    final ali = edit(base, (n) => n.copyWith(name: 'Kalem pil AA'), t0.add(const Duration(minutes: 2)), 'ali');

    final a = mergeNode(ayse, ali);
    final b = mergeNode(ali, ayse);
    expect(a.quantity, 2);
    expect(a.name, 'Kalem pil AA');
    expect(sameVersion(a, b), isTrue, reason: 'iki cihaz aynı sonuca varır');
    expect(a.updatedAt, t0.add(const Duration(minutes: 2)));
    expect(a.updatedBy, 'ali');
    // Tekrar birleştirmek bir şey değiştirmez.
    expect(sameVersion(mergeNode(a, ali), a), isTrue);
    expect(sameVersion(mergeNode(a, ayse), a), isTrue);
  });

  test('alışveriş listesi işareti ayrı birleşir: biri listeye ekler, öbürü adedi değiştirir', () {
    final ayse = edit(base, (n) => n.copyWith(wantedAt: t0.add(const Duration(minutes: 1))), t0.add(const Duration(minutes: 1)), 'ayse');
    final ali = edit(base, (n) => n.copyWith(quantity: 0), t0.add(const Duration(minutes: 2)), 'ali');
    final m = mergeNode(ayse, ali);
    expect((m.isWanted, m.quantity), (true, 0));
    expect(sameVersion(m, mergeNode(ali, ayse)), isTrue);
    // Listeden çıkarmak da yayılır.
    final bought = edit(m, (n) => n.copyWith(clearWanted: true), t0.add(const Duration(minutes: 3)), 'ali');
    expect(mergeNode(m, bought).isWanted, isFalse);
  });

  test('aynı grupta son yazan kazanır; aynı anda iki farklı değerde karar her yerde aynı', () {
    final early = edit(base, (n) => n.copyWith(quantity: 1), t0.add(const Duration(minutes: 1)), 'ayse');
    final late = edit(base, (n) => n.copyWith(quantity: 9), t0.add(const Duration(minutes: 3)), 'ali');
    expect(mergeNode(early, late).quantity, 9);
    expect(mergeNode(late, early).quantity, 9);

    final same = t0.add(const Duration(minutes: 4));
    final x = edit(base, (n) => n.copyWith(quantity: 3), same, 'ayse');
    final y = edit(base, (n) => n.copyWith(quantity: 7), same, 'ali');
    expect(mergeNode(x, y).quantity, mergeNode(y, x).quantity);
  });

  test('yer grubu bütün olarak birleşir: eşya iki yerde birden olmaz', () {
    final lost = edit(
      base,
      (n) => n.copyWith(clearParent: true, lostAt: t0.add(const Duration(minutes: 1)), lostFrom: 'mutfak'),
      t0.add(const Duration(minutes: 1)),
      'ayse',
    );
    final moved = edit(base, (n) => n.copyWith(parentId: 'balkon', sortIndex: 3), t0.add(const Duration(minutes: 2)), 'ali');
    final m = mergeNode(lost, moved);
    expect(m.parentId, 'balkon');
    expect(m.isLost, isFalse, reason: 'kayıp bilgisi yeriyle birlikte gider');
    expect(m.lostFrom, isNull);
    expect(sameVersion(m, mergeNode(moved, lost)), isTrue);
  });

  test('boşaltılan alan da birleşir (ör. son kullanma tarihi silindi, konum kaldırıldı)', () {
    final withDate = edit(
      base,
      (n) => n.copyWith(expiresAt: DateTime(2026, 12, 1), lat: 41, lng: 29, locationLabel: 'Ev'),
      t0.add(const Duration(minutes: 1)),
      'ayse',
    );
    final cleared = edit(
      withDate,
      (n) => n.copyWith(clearExpires: true, clearGeo: true),
      t0.add(const Duration(minutes: 2)),
      'ali',
    );
    final m = mergeNode(withDate, cleared);
    expect(m.expiresAt, isNull);
    expect(m.lat, isNull);
    expect(m.locationLabel, isNull);
  });

  test('grup zamanı olmayan eski kayıt: bütün alanları kendi zamanında sayılır', () {
    final legacy = Node(
      id: 'pil',
      parentId: 'mutfak',
      kind: NodeKind.item,
      name: 'Eski ad',
      color: 1,
      sortIndex: 0,
      createdAt: t0,
      updatedAt: t0.add(const Duration(minutes: 10)),
      quantity: 5,
    );
    final newer = edit(base, (n) => n.copyWith(note: 'yeni not'), t0.add(const Duration(minutes: 20)), 'ali');
    final m = mergeNode(legacy, newer);
    expect(m.note, 'yeni not');
    expect(m.name, 'Eski ad', reason: 'eski kaydın adı (10. dk) yenide dokunulmamış addan (0. dk) yeni');
    expect(m.quantity, 5);
  });

  test('zamanlar kayda yazılıp okunur', () {
    final n = edit(base, (n) => n.copyWith(quantity: 3, minQuantity: 1), t0.add(const Duration(minutes: 1)), 'ayse');
    final back = Node.fromMap(n.toMap());
    expect(sameVersion(back, n), isTrue);
    expect(back.minQuantity, 1);
    expect(Node.fromMap({...n.toMap(), 'field_times': 'bozuk'}).fieldTimes, isEmpty);
  });

  test('barkod ayrı grup: biri barkodu kaydeder, öbürü adı değiştirirse ikisi de kalır; bozuk barkod atılır', () {
    final t1 = t0.add(const Duration(minutes: 5));
    final t2 = t0.add(const Duration(minutes: 9));
    final ayse = edit(base, (n) => n.copyWith(barcode: '8690504012345'), t1, 'ayse');
    final ali = edit(base, (n) => n.copyWith(name: 'Kalem pil'), t2, 'ali');
    final one = mergeNode(ayse, ali);
    final two = mergeNode(ali, ayse);
    expect(one.barcode, '8690504012345');
    expect(one.name, 'Kalem pil');
    expect(sameVersion(one, two), isTrue);
    expect(ayse.timeOf(NodeField.barcode), t1.millisecondsSinceEpoch);
    expect(stateStampOf([base], const {}), isNot(stateStampOf([ayse], const {})));

    // Kaldırılan barkod da birleşir.
    final cleared = edit(one, (n) => n.copyWith(clearBarcode: true), t2.add(const Duration(minutes: 1)), 'ali');
    expect(mergeNode(ayse, cleared).barcode, isNull);

    // Yazılıp okunur; ağdan gelen bozuk değer atılır.
    expect(Node.fromMap(ayse.toMap()).barcode, '8690504012345');
    final map = ayse.toMap();
    expect(sanitizeNode(map)!.barcode, '8690504012345');
    expect(sanitizeNode({...map, 'barcode': 12345})!.barcode, isNull);
    expect(sanitizeNode({...map, 'barcode': 'satır\nsonu'})!.barcode, isNull);
    expect(sanitizeNode({...map, 'barcode': 'x' * 81})!.barcode, isNull);
    expect(sanitizeNode({...map, 'barcode': '  ABC-123 /+  '})!.barcode, 'ABC-123 /+', reason: 'Code 39 harf ve işaret taşır');
    expect(sanitizeNode({...map, 'barcode': '   '})!.barcode, isNull);
  });

  test('karşıdan gelen grup zamanları ve en az adet doğrulanır', () {
    final map = base.copyWith(minQuantity: 2).toMap();
    expect(sanitizeNode(map)!.fieldTimes, base.fieldTimes);
    expect(sanitizeNode(map)!.minQuantity, 2);
    expect(sanitizeNode({...map, 'field_times': '{"uydurma":5}'})!.fieldTimes, isEmpty);
    expect(sanitizeNode({...map, 'field_times': 12})!.fieldTimes, isEmpty);
    expect(sanitizeNode({...map, 'min_quantity': -3})!.minQuantity, isNull);
    expect(sanitizeNode({...map, 'min_quantity': 'çok'})!.minQuantity, isNull);
  });

  test('damga, kayıt zamanı aynı kalsa da grup zamanı değişince değişir', () {
    // Birleştiren cihazın kaydı karşıdakinin zamanını taşıyabilir ama bir
    // alanı daha yenidir; damga aynı kalsaydı karşıya hiç gitmezdi.
    final older = bumpFields(base, const [], base.updatedAt.add(const Duration(minutes: 5)), by: 'ali');
    final merged = older.copyWith(fieldTimes: {...older.allFieldTimes, 'note': older.updatedAt.millisecondsSinceEpoch});
    expect(stateStampOf([older], const {}), isNot(stateStampOf([merged], const {})));
  });

  test('aynı değerli sürümde grup "farklı" sayılmaz', () {
    expect(differingFields(base, base.copyWith(note: 'AA', updatedAt: base.updatedAt)), isEmpty);
    expect(differingFields(base, base.copyWith(isFull: true, updatedAt: base.updatedAt)), [NodeField.full]);
  });

  group('düzenleyicinin kaydı', () {
    final t1 = t0.add(const Duration(minutes: 5));
    final t2 = t0.add(const Duration(minutes: 6));

    test('açıkken karşıdan gelen değişiklik korunur; yalnızca bu oturumda değişen grup yazılır', () {
      // Düzenleyici açıldı (base); bu arada karşıda adet 2 oldu ve eşya kilere taşındı.
      final current = edit(base, (n) => n.copyWith(quantity: 2, parentId: 'kiler'), t1, 'ali');
      final draft = base.copyWith(note: 'AAA', updatedAt: base.updatedAt);

      final saved = applyEdits(opened: base, draft: draft, current: current);
      expect(saved.note, 'AAA');
      expect(saved.quantity, 2, reason: 'taslaktaki eski adet geri yazılmaz');
      expect(saved.parentId, 'kiler', reason: 'taslaktaki eski yer geri yazılmaz');
      // Mağaza kaydederken yalnızca notun zamanı ilerler: eski değerler "en yeni" olmaz.
      final stamped = stampChanges(current, saved.copyWith(updatedAt: t2), t2);
      expect(stamped.timeOf(NodeField.note), t2.millisecondsSinceEpoch);
      expect(stamped.timeOf(NodeField.quantity), t1.millisecondsSinceEpoch);
      expect(stamped.timeOf(NodeField.placement), t1.millisecondsSinceEpoch);
    });

    test('aynı grubu kullanıcı da değiştirdiyse onunki geçer; dokunmadığı grup şimdiki haliyle kalır', () {
      final current = edit(base, (n) => n.copyWith(quantity: 2, name: 'Kalem pil'), t1, 'ali');
      final draft = base.copyWith(quantity: 7, updatedAt: base.updatedAt);

      final saved = applyEdits(opened: base, draft: draft, current: current);
      expect(saved.quantity, 7);
      expect(saved.name, 'Kalem pil');
    });

    test('ekler: eklenen eklenir, karşıdan gelen korunur, karşıda adı değişen eski adına dönmez', () {
      Attachment link(String id, [String? name]) =>
          Attachment(id: id, name: name ?? id, addedAt: DateTime(2026, 9, 1), url: 'https://ornek.com/$id');
      final opened = edit(base, (n) => n.copyWith(attachments: [link('kilavuz'), link('garanti')]), t1, 'ayse');
      // Karşıda: kılavuzun adı değişti, garanti çıkarıldı, video eklendi.
      final current = edit(
        opened,
        (n) => n.copyWith(attachments: [link('kilavuz', 'Kullanım kılavuzu'), link('video')]),
        t2,
        'ali',
      );
      // Bu oturumda yalnızca fatura eklendi (taslakta eski iki ek duruyor).
      final draft = opened.copyWith(attachments: [...opened.attachments, link('fatura')], updatedAt: opened.updatedAt);

      final saved = applyEdits(opened: opened, draft: draft, current: current);
      expect(
        {for (final a in saved.attachments) a.id: a.name},
        {'kilavuz': 'Kullanım kılavuzu', 'fatura': 'fatura', 'video': 'video'},
      );
      expect(saved.attachmentTombs.keys, ['garanti']);
    });
  });
}
