import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/services/backup_service.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// "Yalnızca bende": işaretli kayıt ve içindekiler başka cihazlara gitmez.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('envanter_private'));

  tearDown(() {
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  Future<InventoryStore> device(String name) async {
    final dir = Directory('${work.path}/$name')..createSync(recursive: true);
    AppPaths.useDirectory(dir.path);
    await AppDatabase.instance.openForTest(inMemory: false, path: '${dir.path}/envanter.db');
    final store = InventoryStore()..authorId = name;
    await store.init();
    return store;
  }

  Future<Node> add(InventoryStore store, String parent, NodeKind kind, String name) async {
    final n = store.draft(parentId: parent, kind: kind).copyWith(name: name);
    await store.commit(n);
    return store.byId(n.id)!;
  }

  test('özel klasör ve içindekiler karşıya gitmez; damga da değişmez', () async {
    final ayse = await device('ayse');
    final mutfak = await add(ayse, Roots.home, NodeKind.container, 'Mutfak');
    final gunluk = await add(ayse, Roots.home, NodeKind.container, 'Günlüğüm');
    await ayse.setPrivate(gunluk.id, true);
    final defter = await add(ayse, gunluk.id, NodeKind.item, 'Defter');

    expect(ayse.isPrivate(gunluk.id), isTrue);
    expect(ayse.isPrivate(defter.id), isTrue, reason: 'özel klasörün içi de özel');
    expect(ayse.isPrivateRoot(defter.id), isFalse);
    expect(ayse.snapshot().nodes.keys, [mutfak.id]);
    expect(ayse.liveRecordCount, 1);

    // Özel kayıttaki düzenleme karşıya "konuşacak bir şey var" dedirtmez.
    final stamp = ayse.stateStamp;
    await ayse.commit(ayse.byId(defter.id)!.copyWith(note: 'gizli'));
    expect(ayse.stateStamp, stamp);

    // Ali'ye yalnızca Mutfak gider.
    final shared = ayse.snapshot();
    await AppDatabase.instance.close();
    final ali = await device('ali');
    await ali.mergeRemote(nodes: shared.nodes, tombstones: shared.tombstones);
    expect(ali.byId(mutfak.id), isNotNull);
    expect(ali.byId(gunluk.id), isNull);
    expect(ali.byId(defter.id), isNull);
    await AppDatabase.instance.close();
  });

  test('özel yapılan kayda karşıdan gelen düzenleme ve silme uygulanmaz', () async {
    final ayse = await device('ayse');
    final kutu = await add(ayse, Roots.home, NodeKind.container, 'Kutu');
    final shared = ayse.snapshot(); // Ali'nin elindeki eski kopya
    await ayse.setPrivate(kutu.id, true);

    final later = DateTime.now().add(const Duration(minutes: 1));
    final edited = shared.nodes[kutu.id]!.copyWith(name: 'Ali\'nin kutusu', updatedAt: later);
    await ayse.mergeRemote(nodes: {kutu.id: edited}, tombstones: const {});
    expect(ayse.byId(kutu.id)!.name, 'Kutu');

    final purged = later.add(const Duration(minutes: 1)).millisecondsSinceEpoch;
    await ayse.mergeRemote(nodes: const {}, tombstones: {kutu.id: purged});
    expect(ayse.byId(kutu.id), isNotNull, reason: 'özel kayıt karşının silmesiyle gitmez');
    await AppDatabase.instance.close();
  });

  test('yeniden ortak yapılınca içiyle birlikte karşıya gider; dışarı taşınan eşya ortak olur', () async {
    final ayse = await device('ayse');
    final kutu = await add(ayse, Roots.home, NodeKind.container, 'Kutu');
    final pil = await add(ayse, kutu.id, NodeKind.item, 'Pil');
    final tel = await add(ayse, kutu.id, NodeKind.item, 'Tel');
    await ayse.setPrivate(kutu.id, true);
    expect(ayse.snapshot().nodes, isEmpty);

    await ayse.move(tel.id, Roots.home);
    expect(ayse.snapshot().nodes.keys, [tel.id], reason: 'özel klasörden çıkan eşya ortak');

    await ayse.setPrivate(kutu.id, false);
    expect(ayse.snapshot().nodes.keys.toSet(), {kutu.id, pil.id, tel.id});
    await AppDatabase.instance.close();
  });

  test('yedek özel kayıtları ve işaretlerini taşır; geri yüklenince de özel kalır', () async {
    final eski = await device('eski');
    final gunluk = await add(eski, Roots.home, NodeKind.container, 'Günlüğüm');
    await eski.setPrivate(gunluk.id, true);
    final defter = await add(eski, gunluk.id, NodeKind.item, 'Defter');
    final file = await BackupService.export(eski, into: work);
    await AppDatabase.instance.close();

    final yeni = await device('yeni');
    await BackupService.import(file, yeni);
    expect(yeni.byId(defter.id), isNotNull);
    expect(yeni.isPrivate(defter.id), isTrue);
    expect(yeni.snapshot().nodes, isEmpty);
    await AppDatabase.instance.close();
  });

  group('ortak kayıt özel alana alınınca', () {
    /// Ayşe'nin cihazı: Garaj/Matkap ortak, Odam özel. Ali ilk durumu almış.
    Future<({InventoryStore ayse, Node garaj, Node matkap, Node oda})> setup() async {
      final ayse = await device('ayse');
      final garaj = await add(ayse, Roots.home, NodeKind.container, 'Garaj');
      final matkap = await add(ayse, garaj.id, NodeKind.item, 'Matkap');
      final oda = await add(ayse, Roots.home, NodeKind.container, 'Odam');
      await ayse.setPrivate(oda.id, true);
      // Son eşitleme bunlardan sonra: Garaj ve Matkap karşıda var.
      final synced = DateTime.now().add(const Duration(milliseconds: 5));
      ayse.lastSyncAt = () => synced;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return (ayse: ayse, garaj: garaj, matkap: matkap, oda: oda);
    }

    Future<InventoryStore> aliWith(({Map<String, Node> nodes, Map<String, int> tombstones}) first,
        [({Map<String, Node> nodes, Map<String, int> tombstones})? then]) async {
      await AppDatabase.instance.close();
      final ali = await device('ali');
      await ali.mergeRemote(nodes: first.nodes, tombstones: first.tombstones);
      if (then != null) {
        // Ortak kullanımdaki gibi onaylı mod: bu haber onay beklememeli.
        await ali.mergeRemote(nodes: then.nodes, tombstones: then.tombstones, review: true, from: 'ayse');
      }
      return ali;
    }

    test('diğerlerinde eski yerinde kalmaz: çekmecede "Ayşe\'de" durur, onay beklemez', () async {
      final (:ayse, :garaj, :matkap, :oda) = await setup();
      final first = ayse.snapshot();
      await ayse.move(matkap.id, oda.id);
      expect(ayse.isPrivate(matkap.id), isTrue);

      final ali = await aliWith(first, ayse.snapshot());
      final gelen = ali.byId(matkap.id)!;
      expect(gelen.heldBy, 'ayse');
      expect(ali.bucketKey(gelen), Roots.drawer, reason: 'yeri artık belli değil: Ayşe\'de');
      expect(ali.childrenOf(garaj.id), isEmpty);
      expect(ali.pendingCount, 0, reason: 'bilgi amaçlı son haber onaya düşmez');
      expect(ali.byId(oda.id), isNull, reason: 'Ayşe\'nin özel klasörü görünmez');
      await AppDatabase.instance.close();
    });

    test('özel yapılan ortak klasörün içi dağılmaz: klasörün içinde kalır', () async {
      final (:ayse, :garaj, :matkap, oda: _) = await setup();
      final first = ayse.snapshot();
      await ayse.setPrivate(garaj.id, true);

      final ali = await aliWith(first, ayse.snapshot());
      expect(ali.bucketKey(ali.byId(garaj.id)!), Roots.drawer);
      expect(ali.byId(matkap.id)!.parentId, garaj.id);
      await AppDatabase.instance.close();
    });

    test('son eşitlemeden sonra oluşturulup özel alana konan kayıt için haber gitmez', () async {
      final (:ayse, garaj: _, matkap: _, :oda) = await setup();
      final yeni = await add(ayse, Roots.home, NodeKind.item, 'Yeni');
      await ayse.move(yeni.id, oda.id);
      expect(ayse.snapshot().nodes.containsKey(yeni.id), isFalse);
      await AppDatabase.instance.close();
    });

    test('son haber uygulama kapanıp açılsa da gitmeye devam eder', () async {
      final (:ayse, garaj: _, :matkap, :oda) = await setup();
      await ayse.move(matkap.id, oda.id);
      final held = ayse.snapshot().nodes[matkap.id];
      await AppDatabase.instance.close();
      final again = await device('ayse');
      expect(again.snapshot().nodes[matkap.id], held);
      await AppDatabase.instance.close();
    });

    test('Ayşe yeniden ortak yapınca gerçek yeri herkese gider, işaret kalkar', () async {
      final (:ayse, :garaj, :matkap, :oda) = await setup();
      final first = ayse.snapshot();
      await ayse.move(matkap.id, oda.id);
      final held = ayse.snapshot();
      await ayse.move(matkap.id, garaj.id);
      final back = ayse.snapshot();
      expect(back.nodes[matkap.id]!.heldBy, isNull);

      final ali = await aliWith(first, held);
      await ali.mergeRemote(nodes: back.nodes, tombstones: back.tombstones);
      expect(ali.byId(matkap.id)!.parentId, garaj.id);
      expect(ali.byId(matkap.id)!.heldBy, isNull);
      await AppDatabase.instance.close();
    });

    test('Ali eşyayı bir yere koyunca "Ayşe\'de" işareti kalkar', () async {
      final (:ayse, :garaj, :matkap, :oda) = await setup();
      final first = ayse.snapshot();
      await ayse.move(matkap.id, oda.id);
      final ali = await aliWith(first, ayse.snapshot());
      await ali.move(matkap.id, garaj.id);
      expect(ali.byId(matkap.id)!.heldBy, isNull);
      await AppDatabase.instance.close();
    });
  });

  /// "Ortakken özel oldu" haberi yalnızca gerçekten ortak olmuş kayıt için kurulur: mağazaya
  /// özel olarak giren kayıt, son eşitlemeden eski görünse de hiç gönderilmemiştir.
  group('mağazaya özel olarak giren kayıt karşıya gitmez', () {
    /// Ayşe'nin cihazı: özel Odam klasörü ve içinde Günlük.
    Future<({InventoryStore ayse, Node oda, Node gunluk})> setup() async {
      final ayse = await device('ayse');
      final oda = await add(ayse, Roots.home, NodeKind.container, 'Odam');
      final gunluk = await add(ayse, oda.id, NodeKind.item, 'Günlük');
      await ayse.setPrivate(oda.id, true);
      return (ayse: ayse, oda: oda, gunluk: gunluk);
    }

    test('düzenleyici açıkken bir eşitleme bitse de özel klasöre kaydedilen yeni eşya', () async {
      final (:ayse, :oda, gunluk: _) = await setup();
      var synced = DateTime.now();
      ayse.lastSyncAt = () => synced;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // + ile düzenleyici açılır: kaydın oluşturulma anı bu an.
      final draft = ayse.draft(parentId: oda.id, kind: NodeKind.item).copyWith(name: 'Mektuplar', note: 'gizli');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Düzenleyici açıkken başka bir üyeyle eşitleme tamamlanır, sonra kaydedilir.
      synced = DateTime.now();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await ayse.commit(draft);
      expect(ayse.isPrivate(draft.id), isTrue);
      expect(ayse.snapshot().nodes, isEmpty, reason: 'hiç ortak olmamış kayıt için "bende" haberi kurulmaz');
      await AppDatabase.instance.close();
    });

    test('eşitlenmiş envantere aktarılan yedekteki özel kayıtlar', () async {
      final ayse = await device('ayse');
      final mutfak = await add(ayse, Roots.home, NodeKind.container, 'Mutfak');
      // Yedekteki özel klasör ve içi: son eşitlemeden çok eski kayıtlar.
      final old = DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch;
      Node aged(Node n) => Node.fromMap({...n.toMap(), 'created_at': old, 'updated_at': old});
      final belgeler = aged(ayse.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Belgelerim'));
      final pasaport = aged(ayse.draft(parentId: belgeler.id, kind: NodeKind.item).copyWith(name: 'Pasaport'));
      final synced = DateTime.now();
      ayse.lastSyncAt = () => synced;

      await ayse.importBackup(
        nodes: {belgeler.id: belgeler, pasaport.id: pasaport},
        tombstones: const {},
        privateIds: [belgeler.id],
      );
      // Herhangi bir yerel yazım: özel kayıtlar eskiden burada yayınlanıyordu.
      await ayse.commit(ayse.byId(mutfak.id)!.copyWith(name: 'Mutfak dolabı'));
      expect(ayse.isPrivate(pasaport.id), isTrue);
      expect(ayse.snapshot().nodes.keys, [mutfak.id]);
      await AppDatabase.instance.close();
    });

    test('kalıcı silinip Son silinenler\'den dönen özel klasörün içi', () async {
      final (:ayse, :oda, :gunluk) = await setup();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final synced = DateTime.now();
      ayse.lastSyncAt = () => synced;

      await ayse.moveToTrash(oda.id);
      await ayse.deleteForever(oda.id);
      await ayse.restorePurged(oda.id);
      expect(ayse.byId(gunluk.id), isNotNull);
      expect(ayse.snapshot().nodes, isEmpty);
      await AppDatabase.instance.close();
    });

    test('özel klasörün içindeki eşya çöpten çekmeceye dönünce özel kalır', () async {
      final (:ayse, :oda, :gunluk) = await setup();
      await ayse.moveToTrash(gunluk.id);
      await ayse.moveToTrash(oda.id);
      // Klasörü çöpte: eşya çekmeceye döner, artık Odam'ın altında değildir.
      await ayse.restore(gunluk.id);
      expect(ayse.byId(gunluk.id)!.inDrawer, isTrue);
      expect(ayse.isPrivate(gunluk.id), isTrue, reason: 'işaret kaydın kendisine geçer');
      expect(ayse.snapshot().nodes, isEmpty);
      await AppDatabase.instance.close();
    });

    test('kalıcı silinmiş eşya, klasörü çöpteyken Son silinenler\'den dönünce de özel kalır', () async {
      final (:ayse, :oda, :gunluk) = await setup();
      await ayse.moveToTrash(gunluk.id);
      await ayse.deleteForever(gunluk.id);
      await ayse.moveToTrash(oda.id);
      await ayse.restorePurged(gunluk.id);
      expect(ayse.byId(gunluk.id)!.inDrawer, isTrue);
      expect(ayse.isPrivate(gunluk.id), isTrue);
      expect(ayse.snapshot().nodes, isEmpty);
      await AppDatabase.instance.close();
    });
  });
}
