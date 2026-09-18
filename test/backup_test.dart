import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/services/backup_service.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Dışa aktar → yeni kurulum → içe aktar.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory work;

  setUp(() {
    work = Directory.systemTemp.createTempSync('envanter_backup');
  });

  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  /// Temiz bir kurulum: kendi belgeler klasörü, kendi veritabanı.
  Future<InventoryStore> freshDevice(String name) async {
    final dir = Directory('${work.path}/$name')..createSync(recursive: true);
    AppPaths.useDirectory(dir.path);
    await AppDatabase.instance.openForTest();
    final store = InventoryStore()..authorId = name;
    await store.init();
    return store;
  }

  test('envanter dışa aktarılır, yeni kuruluma olduğu gibi aktarılır', () async {
    final eski = await freshDevice('eski');
    final mutfak = eski.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Mutfak');
    await eski.commit(mutfak);
    final tencere = eski.draft(parentId: mutfak.id, kind: NodeKind.item).copyWith(
          name: 'Tencere',
          note: 'Büyük olan',
          quantity: 3,
          imagePath: 'images/tencere.jpg',
        );
    await eski.commit(tencere);
    File(AppPaths.abs('images/tencere.jpg')).writeAsBytesSync([1, 2, 3, 4]);
    AppPaths.forget('images/tencere.jpg');
    final cop = eski.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Atılmış');
    await eski.commit(cop);
    await eski.moveToTrash(cop.id);

    final zip = await BackupService.export(eski, into: work);
    expect(zip.existsSync(), isTrue);
    expect(zip.lengthSync(), greaterThan(0));
    await AppDatabase.instance.close();

    // Yeni telefon: boş uygulama.
    final yeni = await freshDevice('yeni');
    expect(yeni.childrenOf(Roots.home), isEmpty);

    final result = await BackupService.import(zip, yeni);
    expect(result.added, 3, reason: 'çöptekiler de gelir');
    expect(result.photos, 1);
    expect(result.skipped, 0);

    final kutu = yeni.childrenOf(Roots.home).single;
    expect(kutu.name, 'Mutfak');
    final icindeki = yeni.childrenOf(kutu.id).single;
    expect(icindeki.name, 'Tencere');
    expect(icindeki.note, 'Büyük olan');
    expect(icindeki.quantity, 3);
    expect(AppPaths.imageFile('images/tencere.jpg'), isNotNull, reason: 'fotoğraf da geldi');
    expect(yeni.trash.single.name, 'Atılmış');

    // Aynı dosyayı yeniden almak kopya oluşturmaz.
    final again = await BackupService.import(zip, yeni);
    expect(again.added, 0);
    expect(yeni.childrenOf(Roots.home), hasLength(1));
    await AppDatabase.instance.close();
  });

  test('içe aktarma birleştirir: her iki taraftaki kayıtlar korunur', () async {
    final a = await freshDevice('a');
    final ortak = a.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Depo');
    await a.commit(ortak);
    final zip = await BackupService.export(a, into: work);
    await AppDatabase.instance.close();

    final b = await freshDevice('b');
    final kendi = b.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Kendi eşyam');
    await b.commit(kendi);

    await BackupService.import(zip, b);
    expect(
      b.childrenOf(Roots.home).map((n) => n.name),
      containsAll(['Depo', 'Kendi eşyam']),
    );
    await AppDatabase.instance.close();
  });

  test('başka bir dosya içe aktarılmaz', () async {
    final store = await freshDevice('c');
    final foreign = File('${work.path}/baska.zip')..writeAsBytesSync([80, 75, 3, 4, 0, 0]);
    await expectLater(
      BackupService.import(foreign, store),
      throwsA(isA<BackupException>()),
    );
    final text = File('${work.path}/duz.txt')..writeAsStringSync('merhaba');
    await expectLater(
      BackupService.import(text, store),
      throwsA(isA<BackupException>()),
    );
    await AppDatabase.instance.close();
  });

  test('yarıda kesilen içe aktarma son yolunda yarım dosya bırakmaz; sonraki deneme tamamlar', () async {
    final eski = await freshDevice('eski');
    final tencere = eski.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
          name: 'Tencere',
          imagePath: 'images/tencere.jpg',
        );
    await eski.commit(tencere);
    File(AppPaths.abs('images/tencere.jpg')).writeAsBytesSync([1, 2, 3, 4]);
    AppPaths.forget('images/tencere.jpg');
    final zip = await BackupService.export(eski, into: work);
    await AppDatabase.instance.close();

    final yeni = await freshDevice('yeni');
    final photo = File(AppPaths.abs('images/tencere.jpg'));
    final part = '${photo.path}.part';
    // Yazım yarıda kalsın: dosyanın önce yazıldığı yolu bir klasör tutuyor.
    Directory(part).createSync(recursive: true);
    await expectLater(BackupService.import(zip, yeni), throwsA(anything));
    expect(photo.existsSync(), isFalse, reason: 'yarım dosya son yoluna konmaz');
    expect(yeni.childrenOf(Roots.home), isEmpty, reason: 'kayıtlar da aktarılmadı');

    // Engel kalkınca yeniden: önceki denemeden kalmış parça da sorun olmaz.
    Directory(part).deleteSync();
    File(part).writeAsBytesSync([9]);
    final result = await BackupService.import(zip, yeni);
    expect(result.photos, 1);
    expect(photo.readAsBytesSync(), [1, 2, 3, 4]);
    expect(File(part).existsSync(), isFalse);
    await AppDatabase.instance.close();
  });

  test('yedek dosyasının etiketi envantere özgü: benzer adlar aynı öneki almaz', () {
    final a = BackupService.fileLabelFor(id: 'b3f1c2d4-0000-4000-8000-000000000001', name: 'Depo 1');
    final b = BackupService.fileLabelFor(id: 'b3f1c2d4-0000-4000-8000-000000000002', name: 'Depo 2');
    expect(a, startsWith('envanter-depo-'));
    expect(b, startsWith('envanter-depo-'));
    expect(a, isNot(b));
    // Yerel taraf öneki dosya adının ilk rakamına kadar okur ve "en yeni dört yedeği" ona
    // göre sayar: etikete rakam girmez, biri ötekinin başı da olamaz.
    for (final label in [a, b]) {
      expect(label, matches(RegExp(r'^[a-z-]+-$')));
    }
    expect(a.startsWith(b) || b.startsWith(a), isFalse);
    // Latin harfi olmayan adlar da ayrışır; aynı envanter hep aynı etiketi alır.
    final c = BackupService.fileLabelFor(id: 'x', name: '倉庫');
    expect(c, isNot(BackupService.fileLabelFor(id: 'y', name: 'Склад')));
    expect(BackupService.fileLabelFor(id: 'x', name: '倉庫'), c);
  });
}
