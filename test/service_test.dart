import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/core/time_span.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/services/date_alerts.dart';
import 'package:envanter/services/date_notifier.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/fields.dart';
import 'package:envanter/sync/review.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Periyodik bakım: döngü, sonraki bakım, "bakım yapıldı", geçmiş; kayıtta, eşitlemede ve
/// bildirimlerde taşınması.
void main() {
  final at = DateTime(2026, 9, 1);
  Node item({String? every, String? task, DateTime? last, List<ServiceEntry> log = const []}) => Node(
        id: 'k',
        parentId: null,
        kind: NodeKind.item,
        name: 'Kombi',
        color: 0xFFD9D3C7,
        sortIndex: 0,
        createdAt: at,
        updatedAt: at,
        serviceEvery: every,
        serviceTask: task,
        servicedAt: last,
        serviceLog: log,
      );

  group('model', () {
    test('sonraki bakım son bakıma döngü eklenerek; ay sonu kırpılır', () {
      expect(item(every: '1m', last: DateTime(2026, 9, 1)).nextService, DateTime(2026, 10, 1));
      expect(item(every: '1m', last: DateTime(2026, 1, 31)).nextService, DateTime(2026, 2, 28));
      expect(item(every: '1y', last: DateTime(2026, 9, 1)).nextService, DateTime(2027, 9, 1));
      expect(item(every: '1m').nextService, isNull, reason: 'son bakım günü yok');
      expect(item(last: DateTime(2026, 9, 1)).nextService, isNull, reason: 'döngü yok');
      expect(item().hasService, isFalse);
      expect(item(log: [ServiceEntry(DateTime(2026, 3, 2))]).hasService, isTrue, reason: 'yalnızca onarım geçmişi');
    });

    test('durum: pay döngünün dörtte biri, en çok bir hafta; bakım günü "yaklaştı", ertesi gün gecikmiş', () {
      final monthly = item(every: '1m', last: DateTime(2026, 9, 1)); // sonraki 1 Eki, pay 7 gün
      expect(monthly.serviceStateOn(DateTime(2026, 9, 23)), ExpiryState.fine);
      expect(monthly.serviceStateOn(DateTime(2026, 9, 24)), ExpiryState.soon);
      expect(monthly.serviceStateOn(DateTime(2026, 10, 1, 23)), ExpiryState.soon, reason: 'bugün bakım günü');
      expect(monthly.serviceStateOn(DateTime(2026, 10, 2)), ExpiryState.expired);
      final weekly = item(every: '1w', last: DateTime(2026, 9, 1)); // sonraki 8 Eyl, pay 1 gün
      expect(weekly.serviceStateOn(DateTime(2026, 9, 6)), ExpiryState.fine);
      expect(weekly.serviceStateOn(DateTime(2026, 9, 7)), ExpiryState.soon);
      final yearly = item(every: '1y', last: DateTime(2026, 9, 1)); // pay en çok 7 gün
      expect(yearly.serviceStateOn(DateTime(2027, 8, 24)), ExpiryState.fine);
      expect(yearly.serviceStateOn(DateTime(2027, 8, 25)), ExpiryState.soon);
      final daily = item(every: '1d', last: DateTime(2026, 9, 1));
      expect(daily.serviceStateOn(DateTime(2026, 9, 1)), ExpiryState.fine, reason: 'günlükte pay yok: yarın');
      expect(item().serviceStateOn(DateTime(2026, 9, 1)), isNull);
    });

    test('geçmiş en yeni önce, sabit metinle saklanır; bozuk satır atlanır; en çok 100 satır', () {
      final log = [ServiceEntry(DateTime(2026, 1, 5), 'Filtre'), ServiceEntry(DateTime(2026, 6, 1))];
      final text = ServiceEntry.encode(log)!;
      expect(ServiceEntry.decode(text), [
        ServiceEntry(DateTime(2026, 6, 1)),
        ServiceEntry(DateTime(2026, 1, 5), 'Filtre'),
      ]);
      expect(ServiceEntry.encode(log.reversed.toList()), text, reason: 'sıra her cihazda aynı');
      expect(ServiceEntry.encode(const []), isNull);
      final day = DateTime(2026, 2, 1).millisecondsSinceEpoch;
      expect(
        ServiceEntry.decode('[{"d":$day,"n":"a\\nb"},{"d":"x"},{"d":-4},{"d":$day,"n":"${'x' * 201}"},{"d":$day}]'),
        [ServiceEntry(DateTime(2026, 2, 1))],
      );
      expect(ServiceEntry.decode('bozuk'), isEmpty);
      final many = [for (var i = 0; i < 130; i++) ServiceEntry(DateTime(2020, 1, 1 + i))];
      final kept = ServiceEntry.decode(ServiceEntry.encode(many));
      expect(kept, hasLength(ServiceEntry.maxCount));
      expect(kept.first.day, DateTime(2020, 1, 130), reason: 'en yeniler kalır');
      expect(ServiceEntry.add(many, ServiceEntry(DateTime(2030, 1, 1))), hasLength(ServiceEntry.maxCount));
    });

    test('kayıt veritabanından aynen döner; bozuk değerler kayda girmez', () {
      final n = item(
        every: '3m',
        task: 'Filtreyi değiştir',
        last: DateTime(2026, 8, 15),
        log: [ServiceEntry(DateTime(2026, 8, 15), 'Servis: Ahmet usta, 1500 ₺')],
      );
      final back = Node.fromMap(n.toMap());
      expect(back.serviceEvery, '3m');
      expect(back.serviceTask, 'Filtreyi değiştir');
      expect(back.servicedAt, DateTime(2026, 8, 15));
      expect(back.serviceLog, n.serviceLog);
      final raw = n.toMap()
        ..['service_every'] = 'üç ay'
        ..['service_task'] = 'a\nb';
      final bad = Node.fromMap(raw);
      expect(bad.serviceEvery, isNull);
      expect(bad.serviceTask, isNull);
      expect(Node.cleanServiceTask('  Yağla  '), 'Yağla');
    });

    test('ağdan gelen kayıt süzülür, geçmiş sıraya girer', () {
      final raw = item(every: '1y', last: DateTime(2026, 8, 15)).toMap()
        ..['service_every'] = '0m'
        ..['service_task'] = 'x' * 81
        ..['serviced_at'] = 'dün'
        ..['service_log'] = '[{"d":${DateTime(2025, 1, 1).millisecondsSinceEpoch}},'
            '{"d":${DateTime(2026, 1, 1).millisecondsSinceEpoch}}]';
      final clean = sanitizeNode(raw)!;
      expect(clean.serviceEvery, isNull);
      expect(clean.serviceTask, isNull);
      expect(clean.servicedAt, isNull);
      expect(clean.serviceLog.map((e) => e.day), [DateTime(2026, 1, 1), DateTime(2025, 1, 1)]);
      expect(sanitizeNode(item().toMap()..['service_log'] = 42)!.serviceLog, isEmpty);
      expect(kDataVersion, greaterThanOrEqualTo(25));
    });

    test('plan ve kayıt ayrı gruplarda birleşir: biri döngüyü değiştirir, öteki "bakım yapıldı" der', () {
      final base = item(every: '6m', last: DateTime(2026, 3, 1));
      final mine = stampChanges(base, base.copyWith(serviceEvery: '3m'), at.add(const Duration(minutes: 1)));
      final done = base.copyWith(
        servicedAt: DateTime(2026, 9, 1),
        serviceLog: ServiceEntry.add(base.serviceLog, ServiceEntry(DateTime(2026, 9, 1))),
      );
      final theirs = stampChanges(base, done, at.add(const Duration(minutes: 2)));
      final merged = mergeNode(mine, theirs);
      expect(merged.serviceEvery, '3m', reason: 'döngüyü ben değiştirdim');
      expect(merged.servicedAt, DateTime(2026, 9, 1), reason: 'bakımı o yaptı');
      expect(merged.serviceLog, hasLength(1));
      expect(merged.nextService, DateTime(2026, 12, 1));
      final back = mergeNode(theirs, mine);
      expect(
        [back.serviceEvery, back.servicedAt, back.serviceLog],
        [merged.serviceEvery, merged.servicedAt, merged.serviceLog],
        reason: 'değişmeli',
      );
    });

    test('onay listesi bakım değişikliğini söyler', () {
      final a = item(every: '1y', last: DateTime(2026, 1, 1));
      final b = a.copyWith(servicedAt: DateTime(2026, 9, 1), serviceLog: [ServiceEntry(DateTime(2026, 9, 1))]);
      expect(sameContent(a, b), isFalse);
      expect(sameContent(a, a.copyWith()), isTrue);
      final sum = describeChange(PendingChange(nodeId: a.id, incoming: b, purgedAt: null, receivedAt: at), a);
      expect(sum.kind, ChangeKind.edited);
      expect(sum.serviceChanged, isTrue);
      expect(sum.datesChanged, isFalse, reason: 'satın alma ve son kullanma tarihleri değişmedi');
    });

    test('bildirim bakım gününde bir kez; geçmiş gün planlanmaz', () {
      final n = item(every: '1m', last: DateTime(2026, 9, 1));
      TimeSpan warnOf(Node _) => const TimeSpan(7, SpanUnit.day);
      final plan = planDateAlerts(const [], services: [n], warnOf: warnOf, now: DateTime(2026, 9, 20));
      expect(plan.map((a) => a.day), [DateTime(2026, 10, 1)]);
      expect(plan.single.items.single.$2, DateAlertKind.service);
      expect(planDateAlerts(const [], services: [n], warnOf: warnOf, now: DateTime(2026, 10, 1, 10)), isEmpty,
          reason: 'saat dokuzu geçti');
    });

    test('döngü metni', () {
      const tr = TrStrings();
      const en = EnStrings();
      expect(tr.serviceEveryText(const TimeSpan(3, SpanUnit.month)), '3 ayda bir');
      expect(tr.serviceEveryText(const TimeSpan(1, SpanUnit.week)), 'haftada bir');
      expect(tr.serviceEveryText(const TimeSpan(2, SpanUnit.year)), '2 yılda bir');
      expect(tr.serviceEveryText(const TimeSpan(10, SpanUnit.day)), '10 günde bir');
      expect(en.serviceEveryText(const TimeSpan(1, SpanUnit.month)), 'every month');
      expect(en.serviceEveryText(const TimeSpan(6, SpanUnit.month)), 'every 6 months');
    });
  });

  group('mağaza', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppPaths.useDirectory(Directory.systemTemp.createTempSync('envanter_bakim').path);
    });

    late InventoryStore store;

    setUp(() async {
      await AppDatabase.instance.openForTest(inMemory: true);
      store = InventoryStore();
      await store.init();
      await store.updateSettings(store.settings.copyWith(language: AppLanguage.turkish));
    });

    tearDown(() async => AppDatabase.instance.close());

    Future<Node> add(String name, {String? every, DateTime? last, NodeKind kind = NodeKind.item}) async {
      final draft =
          store.draft(parentId: Roots.home, kind: kind).copyWith(name: name, serviceEvery: every, servicedAt: last);
      await store.commit(draft);
      return store.byId(draft.id)!;
    }

    test('"bakım yapıldı" son bakımı bugüne çeker, geçmişe yazar; tarihlere dokunmaz; geri alınır', () async {
      final today = dateOnly(DateTime.now());
      final buy = DateTime(2025, 5, 10);
      var n = await add('Matkap', every: '3m', last: DateTime(2025, 6, 1));
      await store.commit(store.byId(n.id)!.copyWith(purchasedAt: buy, warranty: '2y', expiresAt: DateTime(2030, 1, 1)));
      final before = store.byId(n.id)!;

      await store.markServiced(n.id);
      n = store.byId(n.id)!;
      expect(n.servicedAt, today);
      expect(n.serviceLog, [ServiceEntry(today)]);
      expect(n.nextService, const TimeSpan(3, SpanUnit.month).addTo(today));
      expect(n.purchasedAt, buy);
      expect(n.expiresAt, DateTime(2030, 1, 1));
      expect(n.effectiveWarrantyEnd, DateTime(2027, 5, 10), reason: 'garanti satın almadan sayılır');

      // Aynı gün ikinci dokunuş çift kayıt açmaz.
      await store.markServiced(n.id);
      expect(store.byId(n.id)!.serviceLog, hasLength(1));

      await store.undoServiced(before);
      n = store.byId(n.id)!;
      expect(n.servicedAt, DateTime(2025, 6, 1));
      expect(n.serviceLog, isEmpty);
      expect(n.serviceEvery, '3m');

      // Diske yazılan da aynı: yeniden açılan mağazada.
      await store.markServiced(n.id);
      final reopened = InventoryStore();
      await reopened.init();
      expect(reopened.byId(n.id)!.serviceLog, [ServiceEntry(today)]);
      expect(reopened.byId(n.id)!.serviceEvery, '3m');
    });

    test('bakım listeleri: en yakın önce, klasör de girer, çöptekiler girmez; gelenler ayrıca', () async {
      final today = dateOnly(DateTime.now());
      final late = await add('Klima', every: '1m', last: today.subtract(const Duration(days: 45)));
      final yearAgo = const TimeSpan(1, SpanUnit.year).subtractFrom(today);
      final soon = await add('Araba', every: '1y', last: yearAgo, kind: NodeKind.container);
      final later = await add('Bisiklet', every: '6m', last: today);
      final trashed = await add('Eski fırın', every: '1m', last: today.subtract(const Duration(days: 60)));
      await add('Not tutulmayan');
      await store.moveToTrash(trashed.id);

      expect(store.serviceItems.map((n) => n.id), [late.id, soon.id, later.id]);
      expect(store.serviceDue.map((n) => n.id), [late.id, soon.id]);

      // Bakım yapılınca "gelenler"den düşer, takvimde sona geçer.
      await store.markServiced(late.id);
      expect(store.serviceDue.map((n) => n.id), [soon.id]);
      expect(store.serviceItems.last.id, later.id);
    });

    test('telefon bildirimi bakım gününde; satırında ne yapılacağı', () async {
      final now = DateTime.now();
      final today = dateOnly(now);
      final n = await add('Akvaryum', every: '2w', last: today);
      await store.commit(store.byId(n.id)!.copyWith(serviceTask: 'Suyu değiştir'));
      final next = const TimeSpan(2, SpanUnit.week).addTo(today);
      final alert = store.dateAlerts(now).singleWhere((a) => a.items.any((i) => i.$2 == DateAlertKind.service));
      expect(alert.day, next);
      final rows = DateNotifier.snapshot(store, now: now);
      expect(rows.map((r) => r.line), contains('Bakım zamanı: Suyu değiştir'));
      expect(rows.map((r) => r.name), contains('Akvaryum'));
    });
  });
}
