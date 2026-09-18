import 'dart:io';
import 'dart:ui';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/money.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/data/settings.dart';
import 'package:envanter/services/box_export.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/fields.dart';
import 'package:envanter/sync/review.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Değer: fiyatın yazılması ve okunması, kayıtta ve eşitlemede taşınması, klasör toplamları,
/// değer dökümü.
void main() {
  // Değer dökümü yazı tiplerini paketten okur.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Money', () {
    Money? tl(String text) => Money.parseInput(text, 'TRY');

    test('yazılan tutar iki yazımla da anlaşılır', () {
      expect(tl('1.250,50'), const Money(125050, 'TRY'));
      expect(tl('1,250.50'), const Money(125050, 'TRY'));
      expect(tl('1250'), const Money(125000, 'TRY'));
      expect(tl('12,5'), const Money(1250, 'TRY'));
      expect(tl('12.5'), const Money(1250, 'TRY'));
      expect(tl('1.250'), const Money(125000, 'TRY'), reason: 'üç rakamlı grup binliktir');
      expect(tl('1.250.000'), const Money(125000000, 'TRY'));
      expect(tl(' 99 ₺ '), const Money(9900, 'TRY'));
      expect(tl('0,99'), const Money(99, 'TRY'));
    });

    test('anlaşılmayan tutar ya da birim null', () {
      expect(tl(''), isNull);
      expect(tl('abc'), isNull);
      expect(tl('1.2.3'), isNull);
      expect(tl('1,2,50.1'), isNull);
      expect(tl('-5'), isNull);
      expect(tl('12,345'), const Money(1234500, 'TRY'), reason: 'tek ayırıcı + üç rakam: binlik');
      expect(Money.parseInput('5', 'tl'), isNull, reason: 'birim üç büyük harf');
      expect(tl('9999999999999999'), isNull, reason: 'trilyonu aşan yazım hatası');
    });

    test('kayıttaki metin sabit biçimde gidip gelir', () {
      const m = Money(125050, 'EUR');
      expect(m.encode(), '1250.50 EUR');
      expect(Money.decode('1250.50 EUR'), m);
      expect(Money.decode('0.05 TRY'), const Money(5, 'TRY'));
      expect(Money.clean('1250.5 EUR'), isNull, reason: 'iki ondalık şart');
      expect(Money.clean('1,250.50 EUR'), isNull);
      expect(Money.clean(12), isNull);
      expect(Money.clean(' 10.00 USD '), '10.00 USD');
    });

    test('okunur biçim dile göre', () {
      expect(const Money(125050, 'TRY').format(turkish: true), '1.250,50 ₺');
      expect(const Money(125000, 'TRY').format(turkish: true), '1.250 ₺');
      expect(const Money(125050, 'TRY').format(turkish: false), '₺1,250.50');
      expect(const Money(99, 'USD').format(turkish: false), r'$0.99');
      expect(const Money(150000, 'SEK').format(turkish: true), '1.500 SEK');
      expect(const Money(125050, 'TRY').inputText(turkish: true), '1250,5');
      expect(const Money(125005, 'TRY').inputText(turkish: false), '1250.05');
    });

    test('adetle çarpım taşmaz', () {
      expect(const Money(1999, 'TRY').times(3), const Money(5997, 'TRY'));
      expect(const Money(1999, 'TRY').times(0), const Money(0, 'TRY'));
      final huge = const Money(Money.maxCents, 'TRY').times(1000000);
      expect(huge.cents, Money.maxCents * 1000);
    });

    test('toplam birim birim, büyükten küçüğe', () {
      final t = MoneyTotals()
        ..add(const Money(1000, 'USD'))
        ..add(const Money(50000, 'TRY'))
        ..add(const Money(2500, 'USD'));
      expect(t.amounts, [const Money(50000, 'TRY'), const Money(3500, 'USD')]);
      expect(t.mainCurrency, 'TRY');
      expect(t.format(turkish: true), r'500 ₺ + 35 $');
      expect(MoneyTotals().isEmpty, isTrue);
    });

    test('varsayılan birim telefonun bölgesinden', () {
      expect(Money.localDefault(const Locale('tr', 'TR')), 'TRY');
      expect(Money.localDefault(const Locale('de', 'DE')), 'EUR');
      expect(Money.localDefault(const Locale('en', 'GB')), 'GBP');
      expect(Money.localDefault(const Locale('tr')), 'TRY');
      expect(Money.localDefault(const Locale('en')), 'USD');
    });
  });

  group('kayıt ve eşitleme', () {
    final at = DateTime(2026, 10, 1);
    Node item({String? price, String? serial, int? quantity}) => Node(
          id: 'a',
          parentId: null,
          name: 'Matkap',
          kind: NodeKind.item,
          color: 0xFFD9D3C7,
          sortIndex: 0,
          createdAt: at,
          updatedAt: at,
          price: price,
          serial: serial,
          quantity: quantity,
        );

    test('fiyat ve seri no veritabanından aynen döner; değer adetle çarpılır', () {
      final n = item(price: '625.00 TRY', serial: 'SN-42 / A', quantity: 2);
      final back = Node.fromMap(n.toMap());
      expect(back.price, '625.00 TRY');
      expect(back.serial, 'SN-42 / A');
      expect(back.value, const Money(125000, 'TRY'));
      expect(item(price: '625.00 TRY').value, const Money(62500, 'TRY'), reason: 'adet tutulmuyorsa tek tane');
      expect(item().value, isNull);
    });

    test('bozuk değerler kayda girmez', () {
      final raw = item().toMap()
        ..['price'] = '12,50 TL'
        ..['serial'] = 'a\u0000b';
      final back = Node.fromMap(raw);
      expect(back.price, isNull);
      expect(back.serial, isNull);
      expect(Node.cleanSerial('  X1  '), 'X1');
      expect(Node.cleanSerial('x' * 81), isNull);
    });

    test('ağdan gelen kayıt süzülür', () {
      final raw = item(price: '1.00 TRY', serial: 'ok').toMap()
        ..['price'] = 'çok pahalı'
        ..['serial'] = 'x' * 200;
      final clean = sanitizeNode(raw);
      expect(clean, isNotNull);
      expect(clean!.price, isNull);
      expect(clean.serial, isNull);
      expect(kDataVersion, greaterThanOrEqualTo(24));
    });

    test('fiyat ve seri no ayrı gruplarda birleşir', () {
      final base = item(price: '100.00 TRY', serial: 'A');
      final mine = stampChanges(base, base.copyWith(price: '150.00 TRY'), at.add(const Duration(minutes: 1)));
      final theirs = stampChanges(base, base.copyWith(serial: 'B'), at.add(const Duration(minutes: 2)));
      final merged = mergeNode(mine, theirs);
      expect(merged.price, '150.00 TRY', reason: 'fiyatı ben değiştirdim');
      expect(merged.serial, 'B', reason: 'seri noyu o değiştirdi');
      expect(mergeNode(theirs, mine).price, merged.price, reason: 'değişmeli');
    });

    test('onay listesi fiyat değişikliğini söyler', () {
      final a = item(price: '100.00 TRY');
      final b = a.copyWith(price: '120.00 TRY');
      expect(sameContent(a, b), isFalse);
      final sum = describeChange(
        PendingChange(nodeId: a.id, incoming: b, purgedAt: null, receivedAt: at),
        a,
      );
      expect(sum.priceChanged, isTrue);
      expect(sum.serialChanged, isFalse);
    });
  });

  group('klasör değeri', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppPaths.useDirectory(Directory.systemTemp.createTempSync('envanter_deger').path);
    });

    late InventoryStore store;

    setUp(() async {
      await AppDatabase.instance.openForTest(inMemory: true);
      store = InventoryStore();
      await store.init();
      await store.updateSettings(store.settings.copyWith(language: AppLanguage.turkish));
    });

    tearDown(() async => AppDatabase.instance.close());

    Future<Node> add(String parent, String name, {NodeKind kind = NodeKind.item, String? price, int? quantity}) async {
      var draft = store.draft(parentId: parent, kind: kind).copyWith(name: name, price: price, quantity: quantity);
      await store.commit(draft);
      return store.byId(draft.id)!;
    }

    test('içindekilerin toplamı, alt klasörler dahil; birimler ayrı; değişince yenilenir', () async {
      final mutfak = await add(Roots.home, 'Mutfak', kind: NodeKind.container);
      final dolap = await add(mutfak.id, 'Dolap', kind: NodeKind.container);
      await add(mutfak.id, 'Blender', price: '2500.00 TRY');
      final tabak = await add(dolap.id, 'Tabak', price: '120.00 TRY', quantity: 6);
      await add(dolap.id, 'Kahve makinesi', price: '300.00 USD');
      await add(dolap.id, 'Peçete');

      expect(store.valueOf(dolap.id).amounts, [const Money(72000, 'TRY'), const Money(30000, 'USD')]);
      expect(store.valueOf(mutfak.id).amounts, [const Money(322000, 'TRY'), const Money(30000, 'USD')]);

      // Adet değişince toplam da (önbellek düşer).
      await store.commit(store.byId(tabak.id)!.copyWith(quantity: 4));
      expect(store.valueOf(mutfak.id).centsIn('TRY'), 250000 + 48000);

      // Çöpe giden sayılmaz; çekmecedeki ve ana ekrandaki toplama girer.
      await store.moveToTrash(dolap.id);
      expect(store.valueOf(mutfak.id).amounts, [const Money(250000, 'TRY')]);
      await add(Roots.drawer, 'Saat', price: '1000.00 TRY');
      await add(Roots.home, 'Tablo', price: '500.00 TRY');
      expect(store.totalValue.centsIn('TRY'), 250000 + 100000 + 50000);
    });

    test('sıralama: ana birimdekiler büyükten küçüğe, fiyatsızlar ayrı', () async {
      await add(Roots.home, 'Ucuz', price: '10.00 TRY');
      await add(Roots.home, 'Pahalı', price: '9000.00 TRY');
      await add(Roots.home, 'Dolarlı', price: '50.00 USD');
      await add(Roots.home, 'Fiyatsız');
      final r = store.valueRanking;
      expect(r.priced.map(store.nameOf), ['Pahalı', 'Ucuz', 'Dolarlı']);
      expect(r.unpriced.map(store.nameOf), ['Fiyatsız']);
    });

    test('değer dökümü PDF olarak üretilir; klasöre de daraltılır', () async {
      final mutfak = await add(Roots.home, 'Mutfak', kind: NodeKind.container);
      await add(mutfak.id, 'Blender', price: '2500.00 TRY');
      await add(mutfak.id, 'Kaşık');
      await add(Roots.home, 'Halı', price: '40.00 AZN');
      final (title, bytes) = await BoxExportService.valuePdf(store);
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(title, store.strings.appTitle, reason: 'testte kütüphane yok: uygulamanın adı');
      final (folderTitle, folderBytes) = await BoxExportService.valuePdf(store, container: mutfak);
      expect(folderTitle, 'Mutfak');
      expect(folderBytes.length, greaterThan(1000));
    });

    test('varsayılan para birimi envantere ait ayar', () async {
      expect(store.settings.currency, isNull);
      await store.updateSettings(store.settings.copyWith(currency: 'EUR'));
      expect(store.settings.defaultCurrency, 'EUR');
      final reloaded = await AppSettings.load();
      expect(reloaded.currency, 'EUR');
    });
  });
}
