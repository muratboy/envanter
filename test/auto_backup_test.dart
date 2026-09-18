import 'dart:io';

import 'package:archive/archive.dart';
import 'package:envanter/core/app_paths.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/services/auto_backup.dart';
import 'package:envanter/services/backup_service.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Haftalık otomatik yedek: vakti gelince seçilen klasöre yazılır.
void main() {
  late Directory work;
  late InventoryStore store;
  late List<({String uri, String name, List<int> bytes})> written;
  var accept = true;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    work = Directory.systemTemp.createTempSync('envanter_auto');
    AppPaths.useDirectory(work.path);
    await AppDatabase.instance.openForTest(inMemory: true);
    store = InventoryStore();
    await store.init();
    written = [];
    accept = true;
    AutoBackup.tempDir = () async => Directory('${work.path}/tmp')..createSync(recursive: true);
    AutoBackup.write = (uri, path, name, keep) async {
      if (!accept) return false;
      written.add((uri: uri, name: name, bytes: File(path).readAsBytesSync()));
      return true;
    };
    await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Garaj'));
  });

  tearDown(() async {
    await AppDatabase.instance.close();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  Future<void> enable() => store.updateSettings(
        store.settings.copyWith(autoBackupUri: 'content://klasor', autoBackupFolder: 'Yedekler'),
      );

  test('kapalıyken hiçbir şey yazılmaz', () async {
    expect(await AutoBackup.runIfDue(store), isFalse);
    expect(written, isEmpty);
  });

  test('açıkken hiç yedek yoksa yazılır; dosya gerçek bir envanter yedeği', () async {
    await enable();
    final now = DateTime.now();
    expect(await AutoBackup.runIfDue(store, now: now), isTrue);
    expect(written.single.uri, 'content://klasor');
    expect(written.single.name, startsWith('envanter-'));
    final archive = ZipDecoder().decodeBytes(written.single.bytes);
    expect(archive.findFile(BackupService.dataEntry), isNotNull);
    expect(store.settings.lastBackupAt, now, reason: 'hatırlatma da buna bakar');
    expect(store.backupDueAt(now.add(const Duration(days: 20))), isFalse);
  });

  test('bir hafta dolmadan ya da değişen bir şey yoksa yazılmaz', () async {
    await enable();
    final t0 = DateTime.now();
    await AutoBackup.runIfDue(store, now: t0);
    expect(await AutoBackup.runIfDue(store, now: t0.add(const Duration(days: 3))), isFalse);
    expect(await AutoBackup.runIfDue(store, now: t0.add(const Duration(days: 10))), isFalse, reason: 'değişiklik yok');

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap'));
    expect(await AutoBackup.runIfDue(store, now: t0.add(const Duration(days: 10))), isTrue);
    expect(written, hasLength(2));
  });

  test('yazılamazsa (izin gitti) işaretlenir; yedek alınmış sayılmaz', () async {
    await enable();
    accept = false;
    expect(await AutoBackup.runIfDue(store), isFalse);
    expect(store.settings.autoBackupFailedAt, isNotNull);
    expect(store.settings.lastBackupAt, isNull);

    accept = true;
    expect(await AutoBackup.run(store), isTrue);
    expect(store.settings.autoBackupFailedAt, isNull, reason: 'başarılı yazımda uyarı kalkar');
  });

  test('klasör ayarı cihazda kalıcı', () async {
    await enable();
    final again = InventoryStore();
    await again.init();
    expect(again.settings.autoBackupUri, 'content://klasor');
    expect(again.settings.autoBackupFolder, 'Yedekler');
  });
}
