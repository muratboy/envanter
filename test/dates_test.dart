import 'dart:convert';
import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/core/time_span.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/services/date_alerts.dart';
import 'package:envanter/services/shopping_widget.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/review.dart';
import 'package:envanter/sync/wire.dart';
import 'package:envanter/ui/shopping_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Satın alma, son kullanma, garanti ve son kullanma uyarısı.
void main() {
  group('süre', () {
    test('kısa metin olarak okunur ve yazılır; bozuk ya da sıfır süre yok sayılır', () {
      expect(TimeSpan.parse('3m'), const TimeSpan(3, SpanUnit.month));
      expect(TimeSpan.parse('10d')!.encode(), '10d');
      expect(TimeSpan.parse('2w'), const TimeSpan(2, SpanUnit.week));
      expect(TimeSpan.parse('1y'), const TimeSpan(1, SpanUnit.year));
      for (final bad in [null, '', '0m', '3', 'm', '3x', '-1d', '12345d']) {
        expect(TimeSpan.parse(bad), isNull, reason: '$bad');
      }
    });

    test('ay ve yıl takvime göre eklenir; ayın sonu kırpılır', () {
      expect(const TimeSpan(1, SpanUnit.month).addTo(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
      expect(const TimeSpan(1, SpanUnit.month).addTo(DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
      expect(const TimeSpan(1, SpanUnit.year).addTo(DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
      expect(const TimeSpan(3, SpanUnit.month).subtractFrom(DateTime(2026, 5, 31)), DateTime(2026, 2, 28));
      expect(const TimeSpan(10, SpanUnit.day).addTo(DateTime(2026, 12, 25, 18)), DateTime(2027, 1, 4));
      expect(const TimeSpan(2, SpanUnit.week).addTo(DateTime(2026, 3, 20)), DateTime(2026, 4, 3));
    });

    test('uyarı süresine girince "yaklaştı", son gün de dahil; ertesi gün "geçti"', () {
      final end = DateTime(2026, 12, 31);
      const warn = TimeSpan(1, SpanUnit.month);
      expect(expiryStateOf(end, warn, DateTime(2026, 11, 29)), ExpiryState.fine);
      expect(expiryStateOf(end, warn, DateTime(2026, 11, 30)), ExpiryState.soon);
      expect(expiryStateOf(end, warn, DateTime(2026, 12, 31, 23, 59)), ExpiryState.soon);
      expect(expiryStateOf(end, warn, DateTime(2027, 1, 1)), ExpiryState.expired);
    });

    test('gün farkı yaz saati geçişinde de tam gün', () {
      expect(daysBetween(DateTime(2026, 3, 28, 23), DateTime(2026, 3, 30, 1)), 2);
      expect(daysBetween(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
      expect(daysBetween(DateTime(2026, 1, 5), DateTime(2026, 1, 2)), -3);
    });

    test('metinler iki dilde', () {
      const tr = TrStrings();
      const en = EnStrings();
      expect(tr.spanText(const TimeSpan(3, SpanUnit.month)), '3 ay');
      expect(en.spanText(const TimeSpan(1, SpanUnit.year)), '1 year');
      expect(en.spanText(const TimeSpan(2, SpanUnit.week)), '2 weeks');
      expect(tr.formatDate(DateTime(2026, 10, 12)), '12 Eki 2026');
      expect(en.formatDate(DateTime(2026, 10, 12)), '12 Oct 2026');
    });
  });

  group('telefon bildirimi planı', () {
    Node item(String name, {DateTime? expires, String? warn, DateTime? warrantyEnd}) => Node(
          id: name,
          parentId: null,
          kind: NodeKind.item,
          name: name,
          color: 0,
          sortIndex: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          expiresAt: expires,
          expiryWarn: warn,
          warrantyEndsAt: warrantyEnd,
        );
    const month = TimeSpan(1, SpanUnit.month);
    TimeSpan warnOf(Node n) => TimeSpan.parse(n.expiryWarn) ?? month;
    final now = DateTime(2026, 10, 1, 8);

    test('uyarı günü ve son gün sabah dokuzda; aynı güne düşenler tek bildirim', () {
      final plan = planDateAlerts([
        item('Süt', expires: DateTime(2026, 11, 20)),
        item('Yoğurt', expires: DateTime(2026, 11, 20)),
        item('Bisküvi', expires: DateTime(2026, 12, 15), warn: '5d'),
      ], warnOf: warnOf, now: now);
      expect(plan.map((a) => a.day), [
        DateTime(2026, 10, 20), // Süt ve yoğurt: bir ay kala
        DateTime(2026, 11, 20), // son gün
        DateTime(2026, 12, 10), // bisküvi: kendi süresi 5 gün
        DateTime(2026, 12, 15),
      ]);
      expect(plan.first.items.map((e) => e.$1.name), ['Süt', 'Yoğurt']);
      expect(plan.first.items.every((e) => e.$2 == DateAlertKind.expiring), isTrue);
      expect(plan[1].items.first.$2, DateAlertKind.lastDay);
      expect(plan.first.at, DateTime(2026, 10, 20, notifyHour));
    });

    test('geçmiş anlar atlanır; bugünün dokuzu geçtiyse bugün de', () {
      final n = item('Peynir', expires: DateTime(2026, 10, 10));
      // Uyarı günü (10 Eylül) geçmiş; yalnızca son gün kalır.
      expect(planDateAlerts([n], warnOf: warnOf, now: now).map((a) => a.day), [DateTime(2026, 10, 10)]);
      final today = item('Ekmek', expires: DateTime(2026, 10, 1));
      expect(planDateAlerts([today], warnOf: warnOf, now: now), hasLength(1), reason: 'saat 8, dokuz gelmedi');
      expect(planDateAlerts([today], warnOf: warnOf, now: DateTime(2026, 10, 1, 10)), isEmpty);
    });

    test('garantinin bitmesine bir ay kala; en fazla 30 gün planlanır', () {
      final plan = planDateAlerts([item('Matkap', warrantyEnd: DateTime(2027, 3, 15))], warnOf: warnOf, now: now);
      expect(plan.single.day, DateTime(2027, 2, 15));
      expect(plan.single.items.single.$2, DateAlertKind.warranty);

      final many = [for (var i = 0; i < 40; i++) item('E$i', expires: DateTime(2027, 1, 1 + i), warn: '1d')];
      expect(planDateAlerts(many, warnOf: warnOf, now: now), hasLength(30));
    });
  });

  group('eşyada', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppPaths.useDirectory(Directory.systemTemp.createTempSync('envanter_dates').path);
    });

    late InventoryStore store;

    setUp(() async {
      await AppDatabase.instance.openForTest(inMemory: true);
      store = InventoryStore();
      await store.init();
      await store.updateSettings(store.settings.copyWith(language: AppLanguage.turkish));
    });

    tearDown(() async => AppDatabase.instance.close());

    Future<Node> item(String name, Node Function(Node n) dates) async {
      final n = dates(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name));
      await store.commit(n);
      return store.byId(n.id)!;
    }

    Future<Node> itemOf(String name, Node Function(Node n) dates) => item(name, dates);

    final today = dateOnly(DateTime.now());

    test('genel uyarı 3 ay; bisküvide 1 ay: yalnızca onda 1 ay önce uyarılır', () async {
      expect(store.settings.expiryWarning, const TimeSpan(3, SpanUnit.month));
      final in2Months = DateTime(today.year, today.month + 2, today.day);
      final longAgo = DateTime(today.year - 1, today.month, today.day); // uzun ömürlü: genel süre geçer
      final pirinc = await item('Pirinç', (n) => n.copyWith(expiresAt: in2Months, purchasedAt: longAgo));
      final biskuvi = await item('Bisküvi', (n) => n.copyWith(expiresAt: in2Months, expiryWarn: '1m'));

      expect(store.expiryOf(pirinc), ExpiryState.soon, reason: '3 aydan az kaldı');
      expect(store.expiryOf(biskuvi), ExpiryState.fine, reason: 'bisküvinin kendi süresi 1 ay');
      expect(store.expiryAlerts.map((n) => n.name), ['Pirinç']);

      // Genel ayar değişince hepsi ona uyar; bisküvi kendi süresinde kalır.
      await store.updateSettings(store.settings.copyWith(expiryWarning: const TimeSpan(1, SpanUnit.week)));
      expect(store.expiryOf(pirinc), ExpiryState.fine);
      expect(store.expiryAlerts, isEmpty);
    });

    test('kendi süresi olmayanda uyarı ömrünün dörtte biri, genel süreyi geçmeden', () async {
      // 10 günlük yoğurt bugün alındı: 3 ay önceden uyarılsa alındığı gün "yaklaştı" olurdu.
      final yogurt = await item('Yoğurt', (n) => n.copyWith(purchasedAt: today, expiresAt: today.add(const Duration(days: 10))));
      expect(store.warnSpanOf(yogurt), const TimeSpan(3, SpanUnit.day));
      expect(store.expiryOf(yogurt), ExpiryState.fine);
      expect(store.expiryOf(yogurt, today.add(const Duration(days: 7))), ExpiryState.soon);
      // Alış günü yoksa eklendiği gün sayılır.
      final sut = await item('Süt', (n) => n.copyWith(expiresAt: today.add(const Duration(days: 8))));
      expect(store.warnSpanOf(sut), const TimeSpan(2, SpanUnit.day));
      // Bir yıllık konserve: dörtte biri genel süreden uzun, genel süre (3 ay) geçer.
      final konserve = await item('Konserve', (n) => n.copyWith(purchasedAt: today, expiresAt: today.add(const Duration(days: 365))));
      expect(store.warnSpanOf(konserve), const TimeSpan(3, SpanUnit.month));
    });

    test('tarihi yazmayan muz: satın alma + raf ömrü; tarih yazılırsa o geçer', () async {
      final bought = today.subtract(const Duration(days: 8));
      final muz = await item('Muz', (n) => n.copyWith(purchasedAt: bought, shelfLife: '1w'));
      expect(muz.effectiveExpiry, bought.add(const Duration(days: 7)));
      expect(store.expiryOf(muz), ExpiryState.expired);

      final yazili = today.add(const Duration(days: 200));
      await store.commit(muz.copyWith(expiresAt: yazili));
      expect(store.byId(muz.id)!.effectiveExpiry, yazili);

      // Satın alma tarihi yoksa raf ömrü tek başına bir şey söylemez.
      final elma = await item('Elma', (n) => n.copyWith(shelfLife: '2w'));
      expect(elma.effectiveExpiry, isNull);
      expect(store.expiryOf(elma), isNull);
    });

    test('garanti: bitiş tarihi yoksa satın alma + garanti süresi', () async {
      final matkap = await item('Matkap', (n) => n.copyWith(purchasedAt: DateTime(2025, 3, 15), warranty: '2y'));
      expect(matkap.effectiveWarrantyEnd, DateTime(2027, 3, 15));
      final tv = await item('TV', (n) => n.copyWith(purchasedAt: DateTime(2025, 1, 1), warranty: '2y',
          warrantyEndsAt: DateTime(2028, 6, 1)));
      expect(tv.effectiveWarrantyEnd, DateTime(2028, 6, 1), reason: 'belgedeki tarih önce gelir');
      expect(store.warranties.map((n) => n.name), ['Matkap', 'TV']);
    });

    test('tükenen, çöpteki ya da klasör uyarı vermez; uyarılar tarih sırasıyla', () async {
      final a = await item('A', (n) => n.copyWith(
            expiresAt: today.add(const Duration(days: 20)),
            purchasedAt: today.subtract(const Duration(days: 300)),
          ));
      await item('B', (n) => n.copyWith(expiresAt: today.subtract(const Duration(days: 1))));
      final c = await item('C', (n) => n.copyWith(expiresAt: today, quantity: 0));
      final d = await item('D', (n) => n.copyWith(expiresAt: today));
      expect(store.expiryAlerts.map((n) => n.name), ['B', 'D', 'A']);

      await store.moveToTrash(d.id);
      expect(store.expiryAlerts.map((n) => n.name), ['B', 'A']);
      expect(store.expiryOf(c), isNull);
      expect(store.expiryOf(store.byId(a.id)!.copyWith(kind: NodeKind.container)), isNull);
    });

    test('alışveriş listesine varsayılan olarak kendiliğinden bir şey girmez; öneri olur, elle eklenir', () async {
      final pil = await item('Pil', (n) => n.copyWith(quantity: 0));
      await item('Deterjan', (n) => n.copyWith(quantity: 2, minQuantity: 3));
      await item('Süt', (n) => n.copyWith(expiresAt: today.subtract(const Duration(days: 2))));
      final ampul = await item('Ampul', (n) => n);
      expect(store.byId(pil.id)!.autoShop, isFalse, reason: 'varsayılan kapalı');
      expect(store.shoppingItems, isEmpty);
      expect(store.shoppingCount, 0);
      expect(store.shoppingSuggestions.map((n) => n.name), ['Pil', 'Deterjan', 'Süt']);

      // Elle: tükenen de, hiçbir durumu olmayan da eklenebilir.
      await store.setWanted(pil.id, true);
      await store.setWanted(ampul.id, true);
      expect(store.shoppingItems.map((n) => n.name), ['Pil', 'Ampul'], reason: 'alınması gereken önce');
      expect(store.shoppingSuggestions.map((n) => n.name), ['Deterjan', 'Süt']);
      expect(ShoppingPage.textOf(store, DateTime(2026, 9, 27)).split('\n'), [
        'Alışveriş listesi · 27 Eyl 2026',
        '• Pil',
        '• Ampul',
      ]);

      // Aldım: adetliye eklenir ve listeden düşer; adetsiz yalnızca düşer; geri alınır.
      final before = store.byId(pil.id)!;
      await store.restock(pil.id, 4);
      expect((store.byId(pil.id)!.quantity, store.byId(pil.id)!.isWanted), (4, false));
      await store.undoBought(before);
      expect((store.byId(pil.id)!.quantity, store.byId(pil.id)!.isWanted), (0, true));
      await store.bought(ampul.id);
      expect(store.shoppingItems.map((n) => n.name), ['Pil']);
      await store.setWanted(pil.id, false);
      expect(store.shoppingItems, isEmpty);
    });

    test('markette işaretlenen listeden düşer, yerleştirilince adedi girer; kartta + de yerleştirir', () async {
      final pil = await item('Pil', (n) => n.copyWith(quantity: 0, wantedAt: today));
      final sut = await item('Süt', (n) => n.copyWith(quantity: 0, wantedAt: today));
      await store.markBought(pil.id);
      expect(store.shoppingItems.map((n) => n.name), ['Süt']);
      expect(store.toPutAway.map((n) => n.name), ['Pil']);
      expect(store.byId(pil.id)!.isWanted, isTrue, reason: 'yerleştirilene dek listede sayılır');
      await store.restock(pil.id, 4);
      expect((store.byId(pil.id)!.quantity, store.byId(pil.id)!.isBought, store.byId(pil.id)!.isWanted), (4, false, false));
      expect(store.toPutAway, isEmpty);

      await store.markBought(sut.id);
      await store.setQuantity(sut.id, 2);
      expect(store.toPutAway, isEmpty, reason: 'elle eklendi: yerleştirilmiş');
      expect(store.shoppingItems, isEmpty);

      // Yanlışlıkla işaretlenen listeye geri döner.
      final ekmek = await item('Ekmek', (n) => n.copyWith(quantity: 0, wantedAt: today));
      await store.markBought(ekmek.id);
      await store.unmarkBought(ekmek.id);
      expect(store.shoppingItems.map((n) => n.name), ['Ekmek']);
    });

    test('"alıyorum" işareti bir gün geçerli; alınınca kalkar', () async {
      store.authorId = 'ayse';
      final pil = await item('Pil', (n) => n.copyWith(quantity: 0, wantedAt: today));
      await store.setBuying(pil.id, true);
      final marked = store.byId(pil.id)!;
      expect(marked.buyingNow(DateTime.now()), 'ayse');
      expect(marked.buyingNow(DateTime.now().add(const Duration(days: 2))), isNull);
      await store.markBought(pil.id);
      expect(store.byId(pil.id)!.buyingBy, isNull);
      expect(Node.fromMap(marked.toMap()).buyingBy, 'ayse', reason: 'kayda yazılır, eşitlenir');
    });

    test('"listeye kendiliğinden ekle" açık eşyalar bitince, azalınca, tarihi geçince girer; aldıkça düşer', () async {
      // Eşyanın kendi ayarı: düzenleyicide açılır.
      Future<Node> auto(String name, Node Function(Node n) change) =>
          item(name, (n) => change(n).copyWith(autoShop: true));
      final pil = await auto('Pil', (n) => n.copyWith(quantity: 0));
      final sut = await auto('Süt', (n) => n.copyWith(expiresAt: today.subtract(const Duration(days: 2))));
      final muz = await auto('Muz', (n) => n.copyWith(
            purchasedAt: today.subtract(const Duration(days: 10)),
            shelfLife: '1w',
          ));
      await auto('Tuz', (n) => n.copyWith(quantity: 3));
      final deterjan = await auto('Deterjan', (n) => n.copyWith(quantity: 2, minQuantity: 3));
      await auto('Sabun', (n) => n.copyWith(quantity: 4, minQuantity: 3));
      final eski = await auto('Eski', (n) => n.copyWith(quantity: 0));
      await store.moveToTrash(eski.id);

      final names = store.shoppingItems.map((n) => n.name).toList();
      expect(names.take(2), ['Pil', 'Deterjan']);
      expect(names.skip(2).toSet(), {'Süt', 'Muz'});
      expect(store.shoppingSuggestions, isEmpty);
      expect(store.shoppingCount, 4);
      expect(ShoppingPage.textOf(store, today).split('\n'), [
        'Alışveriş listesi · ${store.strings.formatDate(today)}',
        '• Pil',
        '• Deterjan (2 kaldı)',
        for (final n in store.shoppingItems.skip(2)) '• ${n.name} (tarihi geçti)',
      ]);

      await store.restock(pil.id, 4);
      expect(store.byId(pil.id)!.quantity, 4);
      // Azalanda alınan, elde kalanın üstüne eklenir.
      await store.restock(deterjan.id, 4);
      expect(store.byId(deterjan.id)!.quantity, 6);

      // Paketli süt: eski tarih silinir, yenisi girilmeli.
      await store.replaced(sut.id, today);
      expect(store.byId(sut.id)!.expiresAt, isNull);
      expect(store.byId(sut.id)!.purchasedAt, today);
      // Muz: raf ömründen yeni tarih kendiliğinden.
      await store.replaced(muz.id, today);
      expect(store.byId(muz.id)!.effectiveExpiry, today.add(const Duration(days: 7)));
      expect(store.shoppingCount, 0);
    });

    test('ana ekran widget\'ı: varsayılan olarak yalnızca elle eklenenler', () async {
      final pil = await item('Pil', (n) => n.copyWith(quantity: 0));
      final ampul = await item('Ampul', (n) => n);
      await item('Süt', (n) => n.copyWith(expiresAt: today.subtract(const Duration(days: 2))));
      await store.setWanted(pil.id, true);
      await store.setWanted(ampul.id, true);
      final payload = jsonDecode(shoppingWidgetPayload(store, today: today)) as Map<String, Object?>;
      final items = (payload['items'] as List).cast<Map<String, Object?>>();
      expect([for (final i in items) (i['name'], i['note'], i['kind'])], [
        ('Pil', 'tükendi', 'out'),
        ('Ampul', '', 'wanted'),
      ]);
    });

    test('ana ekran widget\'ı: kendiliğinden eklenenlerde bugünkü liste ve gün dönünce girecek olanlar', () async {
      Future<Node> item(String name, Node Function(Node n) change) =>
          itemOf(name, (n) => change(n).copyWith(autoShop: true));
      DateTime day(int d) => DateTime(today.year, today.month, today.day + d);
      String iso(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      await item('Pil', (n) => n.copyWith(quantity: 0));
      await item('Deterjan', (n) => n.copyWith(quantity: 2, minQuantity: 3));
      await item('Süt', (n) => n.copyWith(expiresAt: day(-2)));
      await item('Yoğurt', (n) => n.copyWith(expiresAt: day(3)));
      await item('Konserve', (n) => n.copyWith(expiresAt: day(400)));
      // Biten eşyanın tarihi kimseyi ilgilendirmez (uygulamadaki gibi).
      await item('Boş kutu süt', (n) => n.copyWith(quantity: 0, expiresAt: day(-1)));

      final payload = jsonDecode(shoppingWidgetPayload(store, today: today)) as Map<String, Object?>;
      expect((payload['title'], payload['empty']), ('Alışveriş listesi', 'Alınacak bir şey yok'));
      final items = (payload['items'] as List).cast<Map<String, Object?>>();
      expect([for (final i in items) (i['name'], i['note'], i['kind'])], [
        ('Boş kutu süt', 'tükendi', 'out'),
        ('Pil', 'tükendi', 'out'),
        ('Deterjan', '2 kaldı', 'low'),
        ('Süt', 'tarihi geçti', 'expired'),
        ('Yoğurt', 'tarihi geçti', 'expired'),
      ]);
      // Süt zaten listede; yoğurt son gününün ertesinden (dört gün sonra) itibaren.
      expect(items[3].containsKey('from'), isFalse);
      expect(items[4]['from'], iso(day(4)));
      expect(items[0].containsKey('from'), isFalse);
    });

    test('ayarı açık eşya listeye girer, kapalı olan önerilir', () async {
      await item('Pil', (n) => n.copyWith(quantity: 0, autoShop: true));
      await item('Vida', (n) => n.copyWith(quantity: 0));
      expect(store.shoppingItems.map((n) => n.name), ['Pil']);
      expect(store.shoppingSuggestions.map((n) => n.name), ['Vida']);
    });

    test('tarihi geçenler alanı: yerinde duranlar; çöpe, çekmeceye giden ya da biten düşer', () async {
      final kutu = await store.commit(
        store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Buzdolabı'),
      ).then((_) => store.search('Buzdolabı').single);
      Future<Node> inFridge(String name, Node Function(Node n) change) async {
        final n = change(store.draft(parentId: kutu.id, kind: NodeKind.item).copyWith(name: name));
        await store.commit(n);
        return store.byId(n.id)!;
      }

      final sut = await inFridge('Süt', (n) => n.copyWith(expiresAt: today.subtract(const Duration(days: 3))));
      final yogurt = await inFridge('Yoğurt', (n) => n.copyWith(expiresAt: today.subtract(const Duration(days: 1))));
      final peynir = await inFridge('Peynir', (n) => n.copyWith(expiresAt: today.subtract(const Duration(days: 2)), quantity: 2));
      await inFridge('Tereyağı', (n) => n.copyWith(expiresAt: today.add(const Duration(days: 20))));
      expect(store.expiredItems.map((n) => n.name), ['Süt', 'Peynir', 'Yoğurt'], reason: 'en eski tarih önce');
      expect(store.byId(sut.id)!.parentId, kutu.id, reason: 'yerinden kıpırdamaz');

      await store.moveToTrash(sut.id);
      await store.move(yogurt.id, Roots.drawer);
      await store.setQuantity(peynir.id, 0);
      expect(store.expiredItems, isEmpty);
    });

    test('paketler: biri geçince alan işaretler ama alışveriş ancak hepsi geçince; atılınca düşer', () async {
      DateTime day(int d) => DateTime(today.year, today.month, today.day + d);
      final yogurt = await item('Yoğurt', (n) => n.copyWith(
            quantity: 5,
            autoShop: true,
            lots: [Lot(1, day(-2)), Lot(4, day(7))],
          ));
      expect(store.expiredItems.map((n) => n.name), ['Yoğurt'], reason: 'bir paket geçti');
      expect(store.shoppingItems, isEmpty, reason: 'dördü hâlâ iyi: almak gerekmez');
      expect(store.shoppingReason(store.byId(yogurt.id)!), isNull);

      expect(await store.discardExpiredUnits(yogurt.id), 1);
      final after = store.byId(yogurt.id)!;
      expect((after.quantity, after.expiresAt, after.lots), (4, day(7), const <Lot>[]));
      expect(store.expiredItems, isEmpty);

      // Yenileri farklı tarihle alındı: ayrı paket, eldekiler kendi tarihinde.
      await store.restock(yogurt.id, 6, expires: day(20));
      final restocked = store.byId(yogurt.id)!;
      expect(restocked.lots, [Lot(4, day(7)), Lot(6, day(20))]);
      expect(restocked.purchasedAt, today);

      // Hepsi geçince alışveriş listesine girer (ayarı açık).
      final eski = await item('Eski yoğurt', (n) => n.copyWith(
            quantity: 3,
            autoShop: true,
            lots: [Lot(1, day(-5)), Lot(2, day(-1))],
          ));
      expect(store.shoppingItems.map((n) => n.id), [eski.id]);
      await store.replaceExpired(eski.id, 2, expires: day(10));
      final yeni = store.byId(eski.id)!;
      expect((yeni.quantity, yeni.expiresAt), (2, day(10)));
      expect(store.shoppingItems, isEmpty);
    });

    test('her paket tarihi ayrı bildirilir', () {
      final n = Node(
        id: 'y',
        parentId: null,
        kind: NodeKind.item,
        name: 'Yoğurt',
        color: 1,
        sortIndex: 0,
        createdAt: today,
        updatedAt: today,
        quantity: 6,
        lots: [Lot(2, DateTime(2026, 11, 5)), Lot(4, DateTime(2026, 11, 12))],
      );
      final plan = planDateAlerts([n], warnOf: (_) => const TimeSpan(1, SpanUnit.day), now: DateTime(2026, 11, 1));
      expect(plan.map((a) => a.day), [
        DateTime(2026, 11, 4),
        DateTime(2026, 11, 5),
        DateTime(2026, 11, 11),
        DateTime(2026, 11, 12),
      ]);
      expect(plan.last.items.single.$3, DateTime(2026, 11, 12));
    });

    test('genel uyarı süresi cihazda saklanır', () async {
      await store.updateSettings(store.settings.copyWith(expiryWarning: const TimeSpan(6, SpanUnit.week)));
      final again = InventoryStore();
      await again.init();
      expect(again.settings.expiryWarning, const TimeSpan(6, SpanUnit.week));
    });

    test('tarihler veritabanına yazılıp okunur, eşitlemede de gider', () async {
      final n = await item('Süt', (n) => n.copyWith(
            purchasedAt: DateTime(2026, 9, 1),
            expiresAt: DateTime(2026, 9, 20),
            shelfLife: '10d',
            warrantyEndsAt: DateTime(2027, 1, 1),
            warranty: '1y',
            expiryWarn: '3d',
          ));
      final again = InventoryStore();
      await again.init();
      final back = again.byId(n.id)!;
      expect(sameDates(back, n), isTrue);
      expect(sanitizeNode(n.toMap())!.expiryWarn, '3d');

      // Karşıdan bozuk süre ya da tarih gelirse düşer, kayıt kalır.
      final bad = sanitizeNode({...n.toMap(), 'shelf_life': '3 ay', 'expires_at': 'yarın'})!;
      expect(bad.shelfLife, isNull);
      expect(bad.expiresAt, isNull);
      expect(bad.name, 'Süt');

      // Yalnızca tarihi değişen kayıt onayda "tarihler" diye görünür.
      final changed = n.copyWith(expiryWarn: '1w');
      expect(sameContent(n, changed), isFalse);
    });
  });
}
