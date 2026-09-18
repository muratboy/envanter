import 'dart:convert';
import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/core/time_span.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/library.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/data/settings.dart';
import 'package:envanter/services/auto_backup.dart';
import 'package:envanter/services/backup_service.dart';
import 'package:envanter/services/closed_sync.dart';
import 'package:envanter/services/date_notifier.dart';
import 'package:envanter/services/pending_notice.dart';
import 'package:envanter/services/shopping_widget.dart';
import 'package:envanter/state/inventory_host.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/discovery.dart';
import 'package:envanter/sync/sharing_config.dart';
import 'package:envanter/sync/sharing_service.dart';
import 'package:envanter/sync/sync_target.dart';
import 'package:envanter/app.dart';
import 'package:envanter/core/palette.dart';
import 'package:envanter/ui/inventories_page.dart';
import 'package:envanter/ui/sharing/changes_page.dart';
import 'package:envanter/ui/widgets/inventory_emblem.dart';
import 'package:envanter/ui/widgets/paper.dart';
import 'package:envanter/ui/widgets/node_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_inventory.dart';
import 'support/ports.dart';

// Kapalı envanterleri eşitleyen yalıtımın test hazırlığı: yalıtımın kendi
// tekilleri var (veritabanı sürücüsü, kapılar), burada kurulur.
int _visitPort = 0;
int _visitPeer = 0;

void visitSetup(Object? arg) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final ports = arg! as Map;
  _visitPort = ports['port'] as int;
  _visitPeer = ports['peer'] as int;
}

SharingService visitSharing(InventoryStore store, String Function() displayName) => SharingService(
      target: store,
      configStore: MetaSharingConfigStore(),
      displayName: displayName,
      discovery: LanDiscovery(
        port: _visitPort,
        targets: [(InternetAddress.loopbackIPv4, _visitPeer)],
        interval: const Duration(milliseconds: 150),
      ),
      debounce: const Duration(milliseconds: 100),
      joinWait: const Duration(seconds: 3),
      resyncAfter: const Duration(milliseconds: 300),
    );

/// Birden çok envanter (Obsidian'daki kasalar gibi): ayrı veritabanı ve
/// fotoğraf klasörü, envanterden bağımsız kişisel ayarlar, geçiş.
void main() {
  late Directory root;
  late InventoryHost host;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Test bağlamı HTTP'yi taklit ediyor (her isteğe 400); katılma denemesi
    // loopback üzerinden gerçek bağlantı ister.
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> loaded() => host.session.ready;

  Future<InventoryLibrary> library() =>
      InventoryLibrary.load(rootDir: root.path, dbDir: p.join(root.path, 'db'));

  setUp(() async {
    root = Directory.systemTemp.createTempSync('envanter_inventories');
    Directory(p.join(root.path, 'db')).createSync();
    AppPaths.useDirectory(root.path);
    final lib = await library();
    InventoryLibrary.current = lib;
    host = InventoryHost(lib);
    await host.start();
    await loaded();
    await host.session.store.updateSettings(host.session.store.settings.copyWith(language: AppLanguage.turkish));
  });

  tearDown(() async {
    await host.session.ready;
    InventoryLibrary.current = null;
    await AppDatabase.instance.close();
    root.deleteSync(recursive: true);
  });

  Future<Node> add(String name, {Node Function(Node n)? change}) async {
    final store = host.session.store;
    var draft = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name);
    if (change != null) draft = change(draft);
    await store.commit(draft);
    return store.byId(draft.id)!;
  }

  test('ilk envanter eski kurulumun kendisi: veritabanı ve fotoğraflar kökte', () async {
    final lib = host.library;
    expect(lib.entries.map((e) => e.id), [InventoryLibrary.mainId]);
    expect(lib.dbPathOf(InventoryLibrary.mainId), p.join(root.path, 'db', 'envanter.db'));
    expect(lib.docsOf(InventoryLibrary.mainId), root.path);
    expect(File(p.join(root.path, 'inventories.json')).existsSync(), isTrue);
    expect(lib.labelFor('Envanter'), isNull, reason: 'tek envanterde ad eklenmez');
  });

  test('yeni envanter boş açılır; kayıtlar karışmaz, geri dönünce yerinde', () async {
    await add('Matkap');
    final atolye = await host.create('Atölye');
    await loaded();
    expect(host.session.id, atolye.id);
    expect(host.session.store.search('Matkap'), isEmpty);
    expect(AppPaths.docsDir, p.join(root.path, 'inventories', atolye.id));
    expect(File(host.library.dbPathOf(atolye.id)).existsSync(), isTrue);
    await add('Testere');

    await host.open(InventoryLibrary.mainId);
    await loaded();
    expect(host.session.store.search('Matkap').single.name, 'Matkap');
    expect(host.session.store.search('Testere'), isEmpty);
    expect(host.library.byId(atolye.id)!.count, 1, reason: 'kapanırken kayıt sayısı saklanır');

    // Uygulama yeniden açılınca en son açık envanter.
    await host.open(atolye.id);
    final again = await library();
    expect(again.activeId, atolye.id);
    expect(again.byId(atolye.id)!.name, 'Atölye');
  });

  test('güncellemeden sonra hiçbir ayar kaydedilmeden açılan yeni envanter de eski dil ve adla açılır', () async {
    // Eski kurulum: kişisel ayarlar ilk envanterin veritabanında, kütüphane dosyası yok.
    await host.session.ready;
    await AppDatabase.instance.writeMeta('user_name', 'Ali');
    await AppDatabase.instance.writeMeta('language', 'english');
    await AppDatabase.instance.writeMeta('expiry_warn', '5d');
    await AppDatabase.instance.close();
    File(p.join(root.path, 'inventories.json')).deleteSync();
    final lib = await library();
    InventoryLibrary.current = lib;
    host = InventoryHost(lib);
    await host.start();
    await loaded();
    await host.create('Atölye');
    await loaded();
    final other = host.session.store.settings;
    expect(other.userName, 'Ali');
    expect(other.language, AppLanguage.english);
    // Uyarı süresi envantere ait: yeni envanter kendi varsayılanıyla başlar.
    expect(other.expiryWarning, AppSettings.defaultExpiryWarning);
    await host.open(InventoryLibrary.mainId);
    await loaded();
    expect(host.session.store.settings.expiryWarning, const TimeSpan(5, SpanUnit.day));
  });

  test('kişisel ayarlar her envanterde aynı, envantere ait olanlar ayrı', () async {
    final store = host.session.store;
    final matkap = await add('Matkap');
    await store.updateSettings(store.settings.copyWith(userName: 'Ayşe', favorites: [matkap.id]));
    await host.create('Atölye');
    await loaded();
    final other = host.session.store.settings;
    expect(other.userName, 'Ayşe');
    expect(other.language, AppLanguage.turkish);
    expect(other.favorites, isEmpty, reason: 'sık kullanılanlar envantere ait');
    // Kişisel ayar kütüphane dosyasında, envanterin veritabanında değil.
    final json = jsonDecode(File(p.join(root.path, 'inventories.json')).readAsStringSync()) as Map;
    expect((json['global'] as Map)['user_name'], 'Ayşe');
  });

  test('her envanterin kendi ortak kullanımı, onay biçimi, uyarı süresi ve bildirimi var', () async {
    final main = host.session;
    await main.sharing.setAutoAccept(true);
    await main.store.updateSettings(main.store.settings.copyWith(
      expiryWarning: const TimeSpan(1, SpanUnit.month),
      dateNotifications: false,
      groupKinds: false,
    ));
    final today = dateOnly(DateTime.now());
    await add('Süt', change: (n) => n.copyWith(expiresAt: DateTime(today.year, today.month, today.day + 5)));
    final mainInventory = main.sharing.config.inventoryId;

    await host.create('Atölye');
    await loaded();
    final atolye = host.session;
    expect(atolye.sharing.config.autoAccept, isFalse, reason: 'onaylı, ilk envanter otomatik');
    expect(atolye.sharing.config.inventoryId, isNot(mainInventory), reason: 'ayrı ortak kullanım');
    expect(atolye.store.settings.expiryWarning, AppSettings.defaultExpiryWarning);
    expect(atolye.store.settings.dateNotifications, isTrue);
    expect(atolye.store.settings.groupKinds, isTrue);
    // İlk envanterin bildirimi kapalı: kapanırken bildirim satırı saklanmadı.
    expect(host.library.byId(InventoryLibrary.mainId)!.alerts, isEmpty);

    await host.open(InventoryLibrary.mainId);
    await loaded();
    final back = host.session;
    expect(back.sharing.config.autoAccept, isTrue);
    expect(back.sharing.config.inventoryId, mainInventory);
    expect(back.store.settings.expiryWarning, const TimeSpan(1, SpanUnit.month));
    expect(back.store.settings.dateNotifications, isFalse);
    expect(back.store.settings.groupKinds, isFalse);
  });

  test('kapalı envanterin yaklaşan tarihleri saklanır; widget ve yedek adı envanterle', () async {
    final today = dateOnly(DateTime.now());
    await add('Süt', change: (n) => n.copyWith(expiresAt: DateTime(today.year, today.month, today.day + 5)));
    await host.create('Atölye');
    await loaded();
    final main = host.library.byId(InventoryLibrary.mainId)!;
    expect(main.alerts, isNotEmpty);
    expect(main.alerts.every((a) => a.name == 'Süt · Envanter'), isTrue, reason: 'hangi envanterin sütü');

    expect(BackupService.fileLabel(), matches(RegExp(r'^envanter-atolye-[a-z]{6}-$')));
    final payload = jsonDecode(shoppingWidgetPayload(host.session.store, today: today)) as Map;
    expect(payload['title'], 'Alışveriş listesi · Atölye');

    await host.open(InventoryLibrary.mainId);
    expect(BackupService.fileLabel(), 'envanter-', reason: 'ilk envanterin yedekleri eskisi gibi adlanır');
  });

  test('envanterin adı sonradan değişir; açık olanın ağdaki adı da', () async {
    await host.rename(InventoryLibrary.mainId, 'Ev');
    expect(host.library.active.name, 'Ev');
    expect(host.session.sharing.config.inventoryName, 'Ev', reason: 'paylaşan sahip: ağda da bu ad');
    final atolye = await host.create('Atölye');
    await loaded();
    // Kapalı olanın adı da değişir; ağdaki adı açılınca değil, sahibi değiştirince.
    await host.rename(InventoryLibrary.mainId, 'Evim');
    await host.rename(atolye.id, 'Garaj');
    final again = await library();
    expect(again.byId(InventoryLibrary.mainId)!.name, 'Evim');
    expect(again.byId(atolye.id)!.name, 'Garaj');
    expect(host.session.sharing.config.inventoryName, 'Garaj');
  });

  group('renk ve amblem', () {
    final mint = kCardPalette[3].toARGB32();

    test('kütüphanede saklanır; ad değişince ve envanter kapanınca kalır; geri alınır, bozuk değer atılır', () async {
      final atolye = await host.create('Atölye');
      await loaded();
      expect(host.library.byId(atolye.id)!.hasLook, isFalse);
      await host.setColor(atolye.id, mint);
      await host.setGlyph(atolye.id, 'tools');
      var again = await library();
      expect(again.byId(atolye.id)!.color, mint);
      expect(again.byId(atolye.id)!.glyph, 'tools');
      expect(again.byId(InventoryLibrary.mainId)!.hasLook, isFalse, reason: 'öteki envanter kendi görünümünde');

      await host.rename(atolye.id, 'Garaj');
      // Kapanırken kaydın özeti (sayı, yedek, liste) yeniden yazılır: görünüm silinmemeli.
      await host.open(InventoryLibrary.mainId);
      await loaded();
      again = await library();
      expect(again.byId(atolye.id)!.name, 'Garaj');
      expect(again.byId(atolye.id)!.color, mint);
      expect(again.byId(atolye.id)!.glyph, 'tools');

      await host.setColor(atolye.id, null);
      again = await library();
      expect(again.byId(atolye.id)!.color, isNull, reason: 'yalnızca renk kaldırıldı');
      expect(again.byId(atolye.id)!.glyph, 'tools');
      await host.setGlyph(atolye.id, null);
      expect((await library()).byId(atolye.id)!.hasLook, isFalse);

      // Art arda, beklemeden: ikisi de kalır (biri ötekinin eski değerini geri yazmaz).
      final first = host.setColor(atolye.id, mint);
      final second = host.setGlyph(atolye.id, 'book');
      await Future.wait([first, second]);
      again = await library();
      expect(again.byId(atolye.id)!.color, mint);
      expect(again.byId(atolye.id)!.glyph, 'book');
      await host.setGlyph(atolye.id, null);
      await host.setColor(atolye.id, null);

      // Silinenler'e gidip gelen envanter görünümünü korur.
      await host.setColor(atolye.id, mint);
      await host.delete(atolye.id);
      expect(host.library.trashed.single.color, mint);
      await host.restoreDeleted(atolye.id);
      expect(host.library.byId(atolye.id)!.color, mint);

      final broken = InventoryEntry.fromJson({'id': 'a', 'createdAt': 0, 'color': 'kırmızı', 'glyph': '../x'})!;
      expect(broken.hasLook, isFalse);
      // Tanınmayan ama zararsız anahtar saklanır, gösterilirken varsayılan kutuya düşer.
      final unknown = InventoryEntry.fromJson({'id': 'a', 'createdAt': 0, 'glyph': 'spaceship'})!;
      expect(InventoryEmblem.glyphOf(unknown), Icons.inventory_2_rounded);
    });

    testWidgets('envanter listesinden seçilir, hemen uygulanır; başlıkta ve sol menüde görünür', (tester) async {
      const s = TrStrings();
      tester.view.physicalSize = const Size(411, 860) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      // Kütüphane dosyası gerçek zamanda yazılıyor; testin sahte saatinde beklenemez.
      Future<void> settle() async {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(EnvanterRoot(host: host));
      await settle();
      expect(find.byType(InventoryEmblem), findsNothing, reason: 'seçilmediyse başlık eskisi gibi');

      await tester.tap(find.byTooltip(s.menu));
      await tester.pumpAndSettle();
      expect(find.byType(InventoryEmblem), findsNothing, reason: 'menü de');
      await tester.tap(find.byTooltip(s.switchInventory));
      await tester.pumpAndSettle();
      expect(find.byType(InventoriesPage), findsOneWidget);
      // Listede her envanterin bir işareti var; açık olanınkine dokununca seçim açılır.
      await tester.tap(find.byType(InventoryEmblem));
      await tester.pumpAndSettle();
      expect(find.text(s.inventoryLookHint), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('look-$mint')));
      await settle();
      expect(host.library.active.color, mint, reason: 'kaydet yok: dokunuş hemen uygulanır');
      await tester.tap(find.byIcon(Icons.backpack_rounded));
      await settle();
      expect(host.library.active.glyph, 'backpack');
      // Dosyada da. Yazım birkaç adımda biter (aç, yaz, kapat, yeniden adlandır) ve
      // her adım gerçek zamanda, devamı testin saatinde yürür: bitene kadar beklenir.
      InventoryLibrary? onDisk;
      for (var i = 0; i < 40 && onDisk?.active.glyph != 'backpack'; i++) {
        await settle();
        onDisk = await tester.runAsync(library);
      }
      expect(onDisk!.active.glyph, 'backpack');
      expect(onDisk.active.color, mint);
      // Arkadaki liste de değişti (sayfa + seçim sayfasındaki önizleme).
      final shown = tester.widgetList<InventoryEmblem>(find.byType(InventoryEmblem));
      expect(shown.length, 2);
      expect(shown.every((e) => e.entry.color == mint && e.entry.glyph == 'backpack'), isTrue);

      await tester.tap(find.text(s.done));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.back));
      await tester.pumpAndSettle();
      // Ana ekranın başlığında adın önünde.
      final inHeader = find.byType(InventoryEmblem);
      expect(inHeader, findsOneWidget);
      expect(tester.getSize(inHeader), const Size(26, 26));
      final title = tester.getRect(find.text(s.appTitle).first);
      expect(tester.getRect(inHeader).right, lessThan(title.left));
      expect((tester.getRect(inHeader).center.dy - title.center.dy).abs(), lessThan(4), reason: 'adla aynı satırda');

      // Yatayda (tek satırlık başlık) da adın önünde, taşmadan.
      tester.view.physicalSize = const Size(860, 400) * 2;
      await tester.pumpAndSettle();
      expect(find.byType(InventoryEmblem), findsOneWidget);
      expect(tester.getRect(find.byType(InventoryEmblem)).right, lessThan(tester.getRect(find.text(s.appTitle).first).left));
      tester.view.physicalSize = const Size(411, 860) * 2;
      await tester.pumpAndSettle();

      // Sol menünün başlığında da.
      await tester.tap(find.byTooltip(s.menu));
      await tester.pumpAndSettle();
      expect(find.byType(InventoryEmblem), findsNWidgets(2));

      // "Renk yok" + varsayılan amblem: eski sade görünüme döner.
      await tester.tap(find.byTooltip(s.switchInventory));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.options));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.inventoryLook));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('look-none')));
      await settle();
      await tester.tap(find.text(s.defaultIcon));
      await settle();
      expect(host.library.active.hasLook, isFalse);
    });
  });

  test('silinen envanter Silinenler\'e gider, geri getirilir; açık olan da silinir', () async {
    final atolye = await host.create('Atölye');
    await loaded();
    await add('Matkap');
    final photo = File(p.join(host.library.docsOf(atolye.id), 'images', 'foto.jpg'))..writeAsStringSync('x');

    // Açık olan: önce en son açılan başka envantere geçilir.
    expect(await host.delete(atolye.id), isTrue);
    await loaded();
    expect(host.library.activeId, InventoryLibrary.mainId);
    expect(host.library.byId(atolye.id), isNull);
    expect(host.library.trashed.single.id, atolye.id);
    expect(File(host.library.dbPathOf(atolye.id)).existsSync(), isFalse);
    expect(photo.existsSync(), isFalse);
    expect((await library()).trashed.single.name, 'Atölye', reason: 'kütüphane dosyasında da');

    await host.restoreDeleted(atolye.id);
    expect(host.library.trashed, isEmpty);
    await host.open(atolye.id);
    await loaded();
    expect(host.session.store.search('Matkap'), hasLength(1));
    expect(photo.existsSync(), isTrue);

    await host.open(InventoryLibrary.mainId);
    await loaded();
    await host.delete(atolye.id);
    await host.purgeDeleted(atolye.id);
    expect(host.library.trashed, isEmpty);
    expect(Directory(host.library.docsOf(atolye.id)).existsSync(), isFalse);
  });

  test('Silinenler\'de 30 günü geçen açılışta kalıcı silinir', () async {
    final atolye = await host.create('Atölye');
    await loaded();
    await host.open(InventoryLibrary.mainId);
    await loaded();
    await host.library.delete(atolye.id, now: DateTime.now().subtract(const Duration(days: 31)));
    final again = await library();
    expect(again.trashed, isEmpty);
    expect(Directory(p.join(root.path, 'deleted', atolye.id)).existsSync(), isFalse);
  });

  test('tek envanter silinince yerine boş bir envanter açılır; ilk envanterin fotoğrafları gider, kişiselinki kalır', () async {
    final store = host.session.store;
    final avatar = File(p.join(root.path, 'images', 'ben.jpg'))..createSync(recursive: true);
    await store.updateSettings(store.settings.copyWith(userAvatarPath: 'images/ben.jpg'));
    await add('Kalem', change: (n) => n.copyWith(imagePath: 'images/kalem.jpg'));
    final kalem = File(p.join(root.path, 'images', 'kalem.jpg'))..writeAsStringSync('x');

    expect(await host.delete(InventoryLibrary.mainId), isTrue);
    await loaded();
    expect(host.library.entries, hasLength(1));
    expect(host.library.activeId, isNot(InventoryLibrary.mainId));
    expect(host.session.store.totalRecordCount, 0);
    expect(kalem.existsSync(), isFalse);
    expect(avatar.existsSync(), isTrue);

    await host.restoreDeleted(InventoryLibrary.mainId);
    await host.open(InventoryLibrary.mainId);
    await loaded();
    expect(host.session.store.search('Kalem'), hasLength(1));
    expect(kalem.existsSync(), isTrue);
  });

  test('açılamayan veritabanı kenara alınır, envanter boş açılır, arayüze söylenir', () async {
    final atolye = await host.create('Atölye');
    await loaded();
    await add('Matkap');
    await host.open(InventoryLibrary.mainId);
    await loaded();
    File(host.library.dbPathOf(atolye.id)).writeAsStringSync('bu bir veritabanı değil' * 100);

    await host.open(atolye.id);
    await loaded();
    expect(host.takeRecovery(), 'Atölye');
    expect(host.takeRecovery(), isNull, reason: 'bir kez');
    expect(host.session.store.totalRecordCount, 0);
    await add('Yeni');
    expect(host.session.store.search('Yeni'), hasLength(1), reason: 'boş envanter kullanılabilir');
    expect(host.library.trashed.single.name, 'Atölye (açılamayan kopya)');
  });

  test('kapalı envanterde arama ve QR; alışveriş listesi de bu envanterde ve widget\'ta görünür', () async {
    final matkap = await add(
      'Matkap',
      change: (n) => n.copyWith(quantity: 0, wantedAt: DateTime.now(), note: 'darbeli', barcode: '8690504012345'),
    );
    await host.create('Atölye');
    await loaded();

    final hits = host.searchOthers('DARBELİ');
    expect(hits.single.entry.id, InventoryLibrary.mainId);
    expect(hits.single.record.name, 'Matkap');
    expect(hits.single.record.path, isNotEmpty);
    expect(host.findInOthers(matkap.id)?.id, InventoryLibrary.mainId);
    expect(host.searchOthers('testere'), isEmpty);
    // Kapalı envanterdeki eşyanın barkodu da okutunca bulunur.
    expect(host.findBarcodeInOthers('8690504012345')?.record.id, matkap.id);
    expect(host.findBarcodeInOthers('8690504012345')?.entry.id, InventoryLibrary.mainId);
    expect(host.findBarcodeInOthers('1111111111111'), isNull);

    expect(host.library.byId(InventoryLibrary.mainId)!.shopping.single.name, 'Matkap');
    final payload = jsonDecode(shoppingWidgetPayload(host.session.store, today: DateTime.now())) as Map;
    final items = payload['items'] as List;
    expect(items.single['name'], 'Matkap');
    expect(items.single['note'], startsWith('Envanter · '));

    // Aramadan dokununca o envantere geçilir; yeni arayüz kaydı gösterir.
    await host.openAt(InventoryLibrary.mainId, Arrival(InventoryLibrary.mainId, recordId: matkap.id));
    await loaded();
    expect(host.session.id, InventoryLibrary.mainId);
    expect(host.takeArrival()?.recordId, matkap.id);
    expect(host.takeArrival(), isNull);

    // Silinen envanterin dizini aranmaz.
    final atolye = host.library.entries.firstWhere((e) => e.id != InventoryLibrary.mainId);
    await host.open(atolye.id);
    await loaded();
    await host.delete(InventoryLibrary.mainId);
    expect(host.searchOthers('matkap'), isEmpty);
  });

  test('ekranı döndürme ayarı kişisel: bütün envanterlerde aynı', () async {
    final store = host.session.store;
    expect(store.settings.rotateScreen, isTrue, reason: 'varsayılan: telefon dönünce döner');
    await store.updateSettings(store.settings.copyWith(rotateScreen: false));
    await host.create('Atölye');
    await loaded();
    expect(host.session.store.settings.rotateScreen, isFalse);
    expect((await library()).global['rotate_screen'], '0');
  });

  group('otomatik yedek', () {
    late List<String> written;

    setUp(() {
      written = [];
      AutoBackup.tempDir = () async => Directory(p.join(root.path, 'tmp'))..createSync(recursive: true);
      AutoBackup.write = (uri, path, name, keep) async {
        written.add(name);
        return true;
      };
    });

    Future<void> enable() async {
      final store = host.session.store;
      await store.updateSettings(store.settings.copyWith(autoBackupUri: 'content://klasor', autoBackupFolder: 'Yedek'));
    }

    test('klasör kişisel: bütün envanterler için bir kez seçilir', () async {
      await enable();
      await host.create('Atölye');
      await loaded();
      expect(host.session.store.settings.autoBackupFolder, 'Yedek');
    });

    test('değişen envanterden çıkarken yedeklenir; listede son yedeği görünür', () async {
      await enable();
      await add('Kalem');
      final atolye = await host.create('Atölye');
      await loaded();
      expect(written, [startsWith('envanter-2')], reason: 'ilk envanter eski adıyla');
      final main = host.library.byId(InventoryLibrary.mainId)!;
      expect(main.backedUpAt, isNotNull);
      expect(main.needsBackup, isFalse);

      // Değişmeden çıkılan envanter yeniden yazılmaz.
      await host.open(InventoryLibrary.mainId);
      await loaded();
      await host.open(atolye.id);
      await loaded();
      expect(written, hasLength(1));
    });

    test('otomatik yedek açılınca yedeği eksik kapalı envanterler hepsini yedekle ile yazılır', () async {
      await add('Kalem');
      final atolye = await host.create('Atölye');
      await loaded();
      await add('Matkap');
      await host.open(InventoryLibrary.mainId);
      await loaded();
      await enable();
      expect(host.unbackedEntries.map((e) => e.id), [atolye.id]);

      await host.backupAll();
      expect(host.session.id, InventoryLibrary.mainId, reason: 'açık olana dönülür');
      expect(written, contains(startsWith('envanter-atolye-')));
      expect(host.unbackedEntries, isEmpty);
    });
  });

  group('katılırken ayrı envanter', () {
    late SharingService owner;
    late FakeInventory ownerInv;
    late int base;
    bool? decision;

    /// Ayşe'nin ağdaki envanteri ve (katılmak isteyen) bu cihazın ortak
    /// kullanımı loopback üzerinde; kararı [decision] verir.
    Future<DiscoveredPeer> ayseOnNetwork() async {
      base = await takePorts();
      ownerInv = FakeInventory()..add('Tencere');
      owner = SharingService(
        target: ownerInv,
        configStore: MemorySharingConfigStore(),
        displayName: () => 'Ayşe',
        discovery: LanDiscovery(
          port: base,
          targets: [(InternetAddress.loopbackIPv4, base + 1)],
          interval: const Duration(milliseconds: 150),
        ),
        joinWait: const Duration(seconds: 3),
      );
      await owner.load();
      await owner.rename('Ayşe\'nin evi');
      await owner.setEnabled(true);
      owner.addListener(() {
        for (final p in owner.pendingJoins) {
          if (decision != null) owner.decideJoin(p, decision!);
        }
      });
      final lib = host.library;
      await host.session.ready;
      await host.session.sharing.shutdown();
      // Bu cihazın ortak kullanımı da loopback'te: host yeniden kurulur.
      host = InventoryHost(lib, makeSharing: (store, name) => SharingService(
            target: store,
            configStore: MetaSharingConfigStore(),
            displayName: name,
            discovery: LanDiscovery(
              port: base + 1,
              targets: [(InternetAddress.loopbackIPv4, base)],
              interval: const Duration(milliseconds: 150),
            ),
            joinWait: const Duration(seconds: 3),
          ));
      await host.start();
      await loaded();
      await host.session.sharing.setEnabled(true);
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (host.session.sharing.joinableInventories.isEmpty) {
        if (DateTime.now().isAfter(end)) fail('envanter ağda bulunamadı');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return host.session.sharing.joinableInventories.single;
    }

    tearDown(() async {
      await host.session.sharing.shutdown();
      await owner.shutdown();
    });

    test('kabul edilince yeni envanter açılır, buradaki kayıtlar karışmaz', () async {
      await add('Matkap');
      final peer = await ayseOnNetwork();
      decision = true;
      final outcome = await host.joinAsNew(peer, owner: 'Ayşe');
      expect(outcome, JoinOutcome.accepted);
      expect(host.session.id, isNot(InventoryLibrary.mainId));
      expect(host.library.active.name, 'Ayşe\'nin evi');
      final store = host.session.store;
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (store.search('Tencere').isEmpty) {
        if (DateTime.now().isAfter(end)) fail('ortak envanter gelmedi');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(store.search('Matkap'), isEmpty);
      expect(ownerInv.named('Matkap'), isNull, reason: 'ilk envanterin kayıtları Ayşe\'ye gitmez');
      expect(host.takeJoinResult()?.outcome, JoinOutcome.accepted);
    });

    test('reddedilirse boş envanter silinir, öncekine dönülür', () async {
      await add('Matkap');
      final peer = await ayseOnNetwork();
      decision = false;
      final outcome = await host.joinAsNew(peer, owner: 'Ayşe');
      expect(outcome, JoinOutcome.rejected);
      expect(host.session.id, InventoryLibrary.mainId);
      expect(host.library.entries.map((e) => e.id), [InventoryLibrary.mainId]);
      await loaded();
      expect(host.session.store.search('Matkap'), isNotEmpty);
      expect(host.takeJoinResult()?.outcome, JoinOutcome.rejected);
    });
  });

  group('kapalı envanterlerin arka planda eşitlenmesi', () {
    late SharingService ali;
    late FakeInventory aliInv;
    late int base;

    SharingService onLoopback(SyncTarget target, SharingConfigStore config, String Function() name, int port, int peer) =>
        SharingService(
          target: target,
          configStore: config,
          displayName: name,
          discovery: LanDiscovery(
            port: port,
            targets: [(InternetAddress.loopbackIPv4, peer)],
            interval: const Duration(milliseconds: 150),
          ),
          debounce: const Duration(milliseconds: 100),
          joinWait: const Duration(seconds: 3),
          resyncAfter: const Duration(milliseconds: 300),
        );

    Future<void> until(bool Function() ok, String what) async {
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (!ok()) {
        if (DateTime.now().isAfter(end)) fail(what);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    /// Bu cihazın ilk envanteri Ali ile paylaşılır (bu cihaz sahibi), sonra
    /// "Atölye" açılır: paylaşılan envanter kapalı kalır.
    Future<String> sharedThenClosed() async {
      base = await takePorts();
      final lib = host.library;
      await host.session.ready;
      await host.session.sharing.shutdown();
      host = InventoryHost(lib, makeSharing: (store, name) => onLoopback(store, MetaSharingConfigStore(), name, base + 1, base));
      await host.start();
      await loaded();
      await add('Tencere');
      aliInv = FakeInventory();
      ali = onLoopback(aliInv, MemorySharingConfigStore(), () => 'Ali', base, base + 1);
      await ali.load();
      await host.session.sharing.setEnabled(true);
      await ali.setEnabled(true);
      await until(() => ali.joinableInventories.isNotEmpty, 'envanter ağda bulunamadı');
      final request = ali.requestJoin(ali.joinableInventories.single);
      await until(() => host.session.sharing.pendingJoins.isNotEmpty, 'katılma isteği ulaşmadı');
      host.session.sharing.decideJoin(host.session.sharing.pendingJoins.single, true);
      expect(await request, JoinOutcome.accepted);
      await until(() => aliInv.named('Tencere') != null, 'ilk eşitleme olmadı');
      final atolye = await host.create('Atölye');
      await loaded();
      expect(host.library.byId(InventoryLibrary.mainId)!.shared, isTrue);
      return atolye.id;
    }

    Future<int> runClosed({Duration window = const Duration(seconds: 8)}) => ClosedSync.run(
          host,
          window: window,
          platform: false,
          setup: visitSetup,
          setupArg: {'port': base + 1, 'peer': base},
          makeSharing: visitSharing,
        );

    tearDown(() async {
      await ClosedSync.stop();
      await host.session.sharing.shutdown();
      await ali.shutdown();
    });

    test('kapalı paylaşılan envanter eşitlenir: karşıdaki değişiklik onay bekler, işaret ve özet yenilenir; açık envantere dokunulmaz', () async {
      final atolye = await sharedThenClosed();
      expect(host.library.byId(InventoryLibrary.mainId)!.pending, 0);
      // Ali (ana kullanıcı değil) bir eşya ekler; bu cihazda "Atölye" açık.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      aliInv.add('Süt');
      // Bu cihaz da kapalı envanterde olmayan bir şey yaparken...
      await add('Mengene');

      expect(await runClosed(), 1);
      final ev = host.library.byId(InventoryLibrary.mainId)!;
      expect(ev.pending, 1, reason: 'Ali\'nin eklediği onay bekliyor: listede işaret görünür');
      expect(ev.shared, isTrue);
      expect(ev.count, 1, reason: 'onaylanmadan kayıt sayısı değişmez');
      // Dosyaya da yazıldı (yalıtım değil, uygulama yazar).
      expect((await library()).byId(InventoryLibrary.mainId)!.pending, 1);
      expect((await library()).activeId, atolye, reason: 'açık envanter aynı kaldı');
      // Kullanıcı bakmıyordu: telefon bildirimi o envanteri gösterir, ikinci turda yinelenmez.
      final shown = <PendingText>[];
      Future<void> show(PendingText t) async => shown.add(t);
      expect(await PendingNotice.check(host.library, host.session.store, show: show), isTrue);
      expect(shown.single.inventoryId, InventoryLibrary.mainId);
      expect(shown.single.body, host.session.store.strings.pendingInInventory(1));
      expect(await PendingNotice.check(host.library, host.session.store, show: show), isFalse);

      // Açık envanter ve veritabanı bağlantısı yerinde.
      expect(host.session.id, atolye);
      expect(host.session.store.search('Mengene'), hasLength(1));
      await add('Testere');
      expect(host.session.store.totalRecordCount, 2);
      // Bu cihazın durumu da Ali'ye gitti (tur iki yönlü).
      expect(ClosedSync.busy, isFalse);

      // Envanter açılınca bekleyen değişiklik orada; kabul edilince sayı düşer.
      await host.open(InventoryLibrary.mainId);
      await loaded();
      final store = host.session.store;
      expect(store.pendingCount, 1);
      await store.acceptAllChanges();
      expect(store.search('Süt'), hasLength(1));
      await host.open(atolye);
      await loaded();
      expect(host.library.byId(InventoryLibrary.mainId)!.pending, 0, reason: 'kapanırken işaret kalkar');
      expect(host.session.store.search('Testere'), hasLength(1), reason: 'Atölye\'nin kayıtları yerinde');
    });

    testWidgets('onay bekleyen kapalı envanter listede işaretlenir; ayar kapatılıp açılır', (tester) async {
      const s = TrStrings();
      tester.view.physicalSize = const Size(411, 860) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      Future<void> settle() async {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pumpAndSettle();
      }

      // tearDown'ın kapatacağı bir Ali olsun (bu testte ağ yok).
      await tester.runAsync(() async {
        aliInv = FakeInventory();
        ali = onLoopback(aliInv, MemorySharingConfigStore(), () => 'Ali', 1, 2);
        await host.create('Atölye');
        await loaded();
        // İlk envanter kapalı ve içinde iki değişiklik onay bekliyor (arka planda eşitlenmiş gibi).
        await host.library.update(host.library.byId(InventoryLibrary.mainId)!.copyWith(shared: true, pending: 2));
      });
      await tester.pumpWidget(EnvanterRoot(host: host));
      await settle();

      await tester.tap(find.byTooltip(s.menu));
      await tester.pumpAndSettle();
      // Menünün başlığındaki envanter değiştirme simgesinde nokta (eskiden "Envanterler" satırı renklenirdi).
      final switcher = find.byTooltip(s.switchInventory);
      expect(tester.widget<Badge>(find.descendant(of: switcher, matching: find.byType(Badge))).isLabelVisible, isTrue);
      await tester.tap(switcher);
      await tester.pumpAndSettle();
      expect(find.text(s.pendingInInventory(2)), findsOneWidget);
      expect(find.byType(PendingDot), findsOneWidget, reason: 'yalnızca bekleyeni olan envanterde');

      // Ayar kişisel sekmede, varsayılan açık.
      await tester.tap(find.byTooltip(s.back));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.menu));
      await tester.pumpAndSettle();
      // Menü uzun: Ayarlar küçük ekranda aşağıda kalır (tembel listede henüz kurulmamış).
      await tester.scrollUntilVisible(
        find.text(s.settings),
        200,
        scrollable: find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.settings));
      await tester.pumpAndSettle();
      final row = find.widgetWithText(PaperRow, s.syncClosedTitle);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      Switch toggle() => tester.widget<Switch>(find.descendant(of: row, matching: find.byType(Switch)));
      expect(toggle().value, isTrue);
      await tester.tap(row);
      for (var i = 0; i < 6; i++) {
        await settle();
      }
      expect(toggle().value, isFalse);
      expect(host.library.global['sync_closed'], '0');
      expect(host.session.store.settings.syncClosed, isFalse);

      // Bildirim ayarı da orada, varsayılan açık.
      final notify = find.widgetWithText(PaperRow, s.notifyPendingTitle);
      await tester.ensureVisible(notify);
      await tester.pumpAndSettle();
      final notifySwitch = find.descendant(of: notify, matching: find.byType(Switch));
      expect(tester.widget<Switch>(notifySwitch).value, isTrue);
      await tester.tap(notifySwitch);
      for (var i = 0; i < 6; i++) {
        await settle();
      }
      expect(tester.widget<Switch>(notifySwitch).value, isFalse);
      expect(host.library.global['notify_pending'], '0');
    });

    test('onay bekleyen yeni değişiklik bir kez bildirilir; görülen, azalan ve ayarı kapalı olan bildirilmez', () async {
      // tearDown'ın kapatacağı bir Ali olsun (bu testte ağ yok).
      aliInv = FakeInventory();
      ali = onLoopback(aliInv, MemorySharingConfigStore(), () => 'Ali', 1, 2);
      final atolye = await host.create('Atölye');
      await loaded();
      final lib = host.library;
      final store = host.session.store;
      final s = store.strings;
      const main = InventoryLibrary.mainId;
      final shown = <PendingText>[];
      Future<void> show(PendingText t) async => shown.add(t);
      Future<bool> check() => PendingNotice.check(lib, store, show: show);
      Future<void> pending(String id, int count) => lib.update(lib.byId(id)!.copyWith(shared: true, pending: count));

      expect(await check(), isFalse, reason: 'bekleyen yok');

      // Kapalı envanterde iki değişiklik (arka planda eşitlenmiş gibi).
      await pending(main, 2);
      expect(await check(), isTrue);
      expect(shown.last.title, lib.nameOf(lib.byId(main)!, s.appTitle));
      expect(shown.last.body, s.pendingInInventory(2));
      expect(shown.last.inventoryId, main);
      expect(await check(), isFalse, reason: 'aynı sayı yeniden bildirilmez');
      expect(PendingNotice.seen(await library()), {main: 2}, reason: 'arka plan motoru baştan kurulsa da hatırlanır');

      await pending(main, 3);
      expect(await check(), isTrue, reason: 'bir tane daha geldi');
      expect(shown.last.body, s.pendingInInventory(3));

      // Kullanıcı uygulamayı açtı, işareti gördü, çıktı.
      await pending(main, 5);
      await PendingNotice.markSeen(lib, store);
      expect(await check(), isFalse, reason: 'arayüzde gördüğü bildirilmez');

      // Hepsi onaylandı; sonra yenisi geldi.
      await pending(main, 0);
      expect(await check(), isFalse);
      expect(PendingNotice.seen(lib), isEmpty);
      await pending(main, 1);
      expect(await check(), isTrue);

      // İkinci bir kapalı envanter: bildirim ikisini de sayar, tek envantere götürmez.
      await host.create('Depo');
      await loaded();
      final depo = host.session.store;
      await pending(atolye.id, 4);
      expect(await PendingNotice.check(lib, depo, show: show), isTrue);
      expect(shown.last.title, s.pendingNoticeTitle);
      expect(shown.last.inventoryId, isNull);
      expect(shown.last.body, contains('Atölye: ${s.pendingInInventory(4)}'));
      expect(shown.last.body.split('\n'), hasLength(2));

      // Ayar kapalı: sayılar yine izlenir ama bildirim yok.
      final count = shown.length;
      await depo.updateSettings(depo.settings.copyWith(notifyPending: false));
      expect(lib.global['notify_pending'], '0');
      await pending(atolye.id, 6);
      expect(await PendingNotice.check(lib, depo, show: show), isFalse);
      expect(shown, hasLength(count));
      expect(PendingNotice.seen(lib)[atolye.id], 6);
    });

    testWidgets('bildirime dokununca: birkaç envanterse liste, tek envanterse onun değişiklikleri (kapalıysa açılır)', (tester) async {
      tester.view.physicalSize = const Size(411, 860) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      Future<void> settle() async {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pumpAndSettle();
      }

      late String atolye;
      await tester.runAsync(() async {
        aliInv = FakeInventory();
        ali = onLoopback(aliInv, MemorySharingConfigStore(), () => 'Ali', 1, 2);
        atolye = (await host.create('Atölye')).id;
        await loaded();
        await host.library.update(host.library.byId(InventoryLibrary.mainId)!.copyWith(shared: true, pending: 2));
      });
      await tester.pumpWidget(EnvanterRoot(host: host));
      for (var i = 0; i < 3; i++) {
        await settle();
      }

      // Birkaç envanterde bekleyen var: işaretlerin göründüğü liste.
      DateNotifier.instance.tapped(DateNotifier.changesPayload);
      await settle();
      expect(find.byType(InventoriesPage), findsOneWidget);
      expect(find.byType(PendingDot), findsOneWidget);
      await tester.tap(find.byTooltip(const TrStrings().back));
      await tester.pumpAndSettle();

      // Açık envanterin bildirimi: doğrudan değişiklikler.
      DateNotifier.instance.tapped('${DateNotifier.changesPayload}:$atolye');
      await settle();
      expect(find.byType(ChangesPage), findsOneWidget);
      expect(host.session.id, atolye);
      await tester.tap(find.byTooltip(const TrStrings().back));
      await tester.pumpAndSettle();
      expect(find.byType(ChangesPage), findsNothing);

      // Kapalı envanterin bildirimi: o envanter açılır, değişiklikler onun üstünde.
      // Geçiş gerçek dosya işi ve zamanlayıcılarla yürür: testin sahte saatinde değil,
      // gerçek zamanda başlatılıp beklenir (yoksa yarıda kalır ve dosya kapanamaz).
      await tester.runAsync(() async {
        DateNotifier.instance.tapped('${DateNotifier.changesPayload}:${InventoryLibrary.mainId}');
        final end = DateTime.now().add(const Duration(seconds: 10));
        while (host.session.id != InventoryLibrary.mainId && DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await loaded();
      });
      for (var i = 0; i < 4; i++) {
        await settle();
      }
      expect(host.session.id, InventoryLibrary.mainId);
      expect(find.byType(ChangesPage), findsOneWidget);
    });

    test('ayar kapalıysa ya da paylaşılan kapalı envanter yoksa hiçbir şey yapılmaz', () async {
      await sharedThenClosed();
      aliInv.add('Süt');
      await host.session.store.updateSettings(host.session.store.settings.copyWith(syncClosed: false));
      expect(host.library.global['sync_closed'], '0');
      expect(await runClosed(), 0);
      expect(host.library.byId(InventoryLibrary.mainId)!.pending, 0);

      await host.session.store.updateSettings(host.session.store.settings.copyWith(syncClosed: true));
      expect(ClosedSync.targets(host.library, host.session.id).map((e) => e.id), [InventoryLibrary.mainId]);
      // Açık olan envanter hedef değildir (o zaten kendi eşitlenir).
      expect(ClosedSync.targets(host.library, InventoryLibrary.mainId), isEmpty);
    });

    test('durdurulunca yalıtım envanteri bırakır: hemen ardından o envantere geçilebilir', () async {
      await sharedThenClosed();
      await ali.shutdown(); // ağda kimse yok: tur pencerenin sonuna kadar beklerdi
      final watch = Stopwatch()..start();
      final running = runClosed(window: const Duration(seconds: 30));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(ClosedSync.busy, isTrue);
      // Geçiş, süren eşitlemeyi kendisi durdurur ve veritabanının bırakılmasını bekler.
      await host.open(InventoryLibrary.mainId);
      await loaded();
      expect(watch.elapsed, lessThan(const Duration(seconds: 12)), reason: '30 saniyelik pencere beklenmedi');
      expect(ClosedSync.busy, isFalse);
      await running;
      expect(host.session.store.search('Tencere'), hasLength(1));
      await add('Kapak');
      expect(host.session.store.totalRecordCount, 2);
    });
  });

  group('envanterler arası aktarma', () {
    Future<Node> put(String name, String parent, {NodeKind kind = NodeKind.item}) async {
      final store = host.session.store;
      final draft = store.draft(parentId: parent, kind: kind).copyWith(name: name);
      await store.commit(draft);
      return store.byId(draft.id)!;
    }

    /// Yeni bir envanter kurar ve ilk envantere geri döner.
    Future<InventoryEntry> another(String name) async {
      final entry = await host.create(name);
      await loaded();
      await host.open(InventoryLibrary.mainId);
      await loaded();
      return entry;
    }

    Future<InventoryStore> openStore(String id) async {
      await host.open(id);
      await loaded();
      return host.session.store;
    }

    test('kopya yeni kimlik alır; aynı klasörün ikinci kopyası öncekinin içindekilerini silmez', () async {
      final kutu = await put('Kablo kutusu', Roots.home, kind: NodeKind.container);
      await put('HDMI', kutu.id);
      final atolye = await another('Atölye');

      expect(await host.transferNodes(nodes: [kutu], targetInventoryId: atolye.id, isCopy: true), 2);
      expect(host.session.store.byId(kutu.id), isNotNull, reason: 'kopyada kaynak yerinde');

      var store = await openStore(atolye.id);
      final copy = store.search('Kablo kutusu').single;
      expect(copy.id, isNot(kutu.id));
      expect(store.childrenOf(copy.id).map((n) => n.name), ['HDMI']);
      // Hedefte kopyanın içine bir şey eklenir, sonra aynı klasör yeniden kopyalanır: aynı kimlikle
      // "INSERT OR REPLACE" klasörü sil + ekle yapıyor, CASCADE içindekileri siliyordu.
      await put('Yeni kablo', copy.id);
      store = await openStore(InventoryLibrary.mainId);
      expect(await host.transferNodes(nodes: [store.byId(kutu.id)!], targetInventoryId: atolye.id, isCopy: true), 2);

      store = await openStore(atolye.id);
      expect(store.search('Kablo kutusu'), hasLength(2));
      expect(store.childrenOf(copy.id).map((n) => n.name).toSet(), {'HDMI', 'Yeni kablo'});
    });

    test('taşıma kaynaktan çıkarır, hedefin aramasına girer; geri taşınan kayıt eski silme iziyle silinmez', () async {
      final matkap = await add('Matkap');
      final atolye = await another('Atölye');

      expect(await host.transferNodes(nodes: [matkap], targetInventoryId: atolye.id, isCopy: false), 1);
      var store = host.session.store;
      expect(store.byId(matkap.id), isNull);
      expect(store.recentlyPurged.map((r) => r.node.id), contains(matkap.id),
          reason: '30 gün geri getirilebilir');
      expect(host.library.readIndex(atolye.id)!.where((r) => r.id == matkap.id).single.path, 'Ana ekran',
          reason: 'kapalı envanterde arama ve QR etiketi de bulsun');

      store = await openStore(atolye.id);
      expect(store.byId(matkap.id)?.name, 'Matkap', reason: 'taşımada kimlik kalır: basılı QR etiketi çalışsın');
      await host.transferNodes(
        nodes: [store.byId(matkap.id)!],
        targetInventoryId: InventoryLibrary.mainId,
        isCopy: false,
      );

      store = await openStore(InventoryLibrary.mainId);
      expect(store.byId(matkap.id)?.name, 'Matkap');
      expect(await AppDatabase.instance.loadTombstones(), isNot(contains(matkap.id)),
          reason: 'ilk taşımanın izi kalktı');
      expect(store.recentlyPurged.map((r) => r.node.id), isNot(contains(matkap.id)));
    });
  });

  test('ilk envanter silinince kişinin fotoğrafı kalır', () async {
    final store = host.session.store;
    File(p.join(root.path, 'images', 'ben.jpg')).writeAsStringSync('ben');
    File(p.join(root.path, 'images', 'kutu.jpg')).writeAsStringSync('kutu');
    await store.updateSettings(store.settings.copyWith(userAvatarPath: 'images/ben.jpg'));
    await host.create('Atölye');
    await loaded();
    expect(await host.delete(InventoryLibrary.mainId), isTrue);
    expect(File(p.join(root.path, 'images', 'ben.jpg')).existsSync(), isTrue);
    expect(File(p.join(root.path, 'images', 'kutu.jpg')).existsSync(), isFalse);
    // Kütüphane yeniden okununca silinen ilk envanter geri gelmez.
    expect((await library()).entries.map((e) => e.name), ['Atölye']);
  });
}
