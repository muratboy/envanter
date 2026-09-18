import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/services/backup_service.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sık kullanılanlar cihaza özeldir: kayıtlarla birlikte gezmez.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory work;

  setUp(() {
    work = Directory.systemTemp.createTempSync('envanter_fav');
  });

  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  /// Kendi belgeler klasörü ve veritabanı dosyası olan bir cihaz. Aynı adla
  /// yeniden çağırmak o cihazı yeniden açar (uygulamayı kapatıp açmak gibi).
  Future<InventoryStore> device(String name) async {
    final dir = Directory('${work.path}/$name')..createSync(recursive: true);
    AppPaths.useDirectory(dir.path);
    await AppDatabase.instance.openForTest(inMemory: false, path: '${dir.path}/envanter.db');
    final store = InventoryStore()..authorId = name;
    await store.init();
    return store;
  }

  test('ortak kullanımda favoriler karşıya geçmez, kayıtlar geçer', () async {
    final ayse = await device('ayse');
    final mutfak = ayse.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Mutfak');
    await ayse.commit(mutfak);
    final tuz = ayse.draft(parentId: mutfak.id, kind: NodeKind.item).copyWith(name: 'Tuz');
    await ayse.commit(tuz);
    await ayse.toggleFavorite(mutfak.id);
    expect(ayse.isFavorite(mutfak.id), isTrue);
    expect(ayse.favorites.single.name, 'Mutfak');

    // Ayşe'nin karşıya gönderdiği her şey.
    final shared = ayse.snapshot();
    final backup = await BackupService.export(ayse, into: work);
    await AppDatabase.instance.close();

    // Ali ortak kullanıma katılıyor: kayıtlar gelir, favoriler gelmez.
    final ali = await device('ali');
    await ali.mergeRemote(nodes: shared.nodes, tombstones: shared.tombstones);
    expect(ali.byId(mutfak.id), isNotNull, reason: 'kayıt eşitlendi');
    expect(ali.byId(tuz.id), isNotNull);
    expect(ali.favorites, isEmpty, reason: 'favoriler Ayşe’de kalır');
    expect(ali.isFavorite(mutfak.id), isFalse);
    expect(ali.settings.favorites, isEmpty);

    // Yedek dosyası da taşımaz.
    await BackupService.import(backup, ali);
    expect(ali.favorites, isEmpty);
    expect(ali.settings.favorites, isEmpty);
    // Ayşe'nin son dokundukları ve yedek zamanı da onda kalır.
    expect(ayse.settings.recent, isNotEmpty);
    expect(ali.recent, isEmpty);
    expect(ali.settings.lastBackupAt, isNull);

    // Ali kendi favorisini seçer; bu da Ayşe'ye gitmez.
    await ali.toggleFavorite(tuz.id);
    final fromAli = ali.snapshot();
    await AppDatabase.instance.close();

    final ayseAgain = await device('ayse');
    await ayseAgain.mergeRemote(nodes: fromAli.nodes, tombstones: fromAli.tombstones);
    expect(ayseAgain.favorites.map((n) => n.id), [mutfak.id], reason: 'kendi listesi durur');
    expect(ayseAgain.isFavorite(tuz.id), isFalse, reason: 'Ali’nin favorisi gelmez');
    await AppDatabase.instance.close();
  });

  test('favoriler bu cihazda kalıcıdır', () async {
    final store = await device('tek');
    final kutu = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
    await store.commit(kutu);
    await store.toggleFavorite(kutu.id);
    await AppDatabase.instance.close();

    // Uygulama kapanıp açıldı.
    final again = await device('tek');
    expect(again.isFavorite(kutu.id), isTrue);
    expect(again.favorites.single.name, 'Kutu');
    await AppDatabase.instance.close();
  });

  test('kalıcı silinen kayıt favorilerden düşer', () async {
    final store = await device('tek');
    final kutu = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
    await store.commit(kutu);
    await store.toggleFavorite(kutu.id);
    expect(store.settings.favorites, [kutu.id]);

    await store.moveToTrash(kutu.id);
    expect(store.favorites, isEmpty, reason: 'çöptekiler listede görünmez');
    expect(store.settings.favorites, [kutu.id], reason: 'geri alınabilir, kimlik durur');

    await store.deleteForever(kutu.id);
    expect(store.settings.favorites, isEmpty);
    await AppDatabase.instance.close();
  });
}
