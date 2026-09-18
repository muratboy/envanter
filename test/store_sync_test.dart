import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/review.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Gerçek mağaza + gerçek veritabanı. İki telefon sırayla açılıp kapanıyor;
/// aralarında yalnızca SyncState (ağda giden JSON) ve resim baytları gidiyor.
class Phone {
  Phone(this.name, Directory root)
      : dbPath = p.join(root.path, '$name.db'),
        docs = Directory(p.join(root.path, '$name-docs'))..createSync();

  final String name;
  final String dbPath;
  final Directory docs;
  late InventoryStore store;

  Future<void> open() async {
    AppPaths.useDirectory(docs.path);
    await AppDatabase.instance.openForTest(inMemory: false, path: dbPath);
    store = InventoryStore()..authorId = name;
    await store.init();
    await store.updateSettings(store.settings.copyWith(language: AppLanguage.turkish));
  }

  /// Ağda gidecek durum, JSON'a yazılıp geri okunarak (gerçekteki gibi).
  SyncState outgoing() {
    final snap = store.snapshot();
    final state = SyncState(nodes: snap.nodes, tombstones: snap.tombstones, members: const []);
    return SyncState.fromJson(jsonDecode(jsonEncode(state.toJson())));
  }

  Future<void> merge(SyncState state) =>
      store.mergeRemote(nodes: state.nodes, tombstones: state.tombstones);

  /// Onaylı mod: değişiklik beklemeye alınır.
  Future<void> review(SyncState state, {String? from}) =>
      store.mergeRemote(nodes: state.nodes, tombstones: state.tombstones, review: true, from: from);

  Node named(String title) => store.search(title).firstWhere((n) => n.name == title);

  Future<Node> add(String parent, NodeKind kind, String title, {String? image}) async {
    var draft = store.draft(parentId: parent, kind: kind).copyWith(name: title);
    if (image != null) {
      final rel = 'images/$image';
      File(p.join(docs.path, rel)).writeAsStringSync('foto:$image');
      AppPaths.forget(rel);
      draft = draft.copyWith(imagePath: rel);
    }
    await store.commit(draft);
    return store.byId(draft.id)!;
  }

  bool has(String title) => store.search(title).any((n) => n.name == title);

  /// Ağa giden durumun damgası: iki cihazın aynı yere varıp varmadığı.
  String get stamp => stampOf(outgoing());
}

String stampOf(SyncState s) => stateStampOf(s.nodes.values, s.tombstones);

void main() {
  late Directory root;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => root = Directory.systemTemp.createTempSync('envanter_store_sync'));
  tearDown(() async {
    await AppDatabase.instance.close();
    root.deleteSync(recursive: true);
  });

  test('birleşme ve silme izleri uygulama yeniden açılınca da durur', () async {
    final ayse = Phone('ayse', root);
    final ali = Phone('ali', root);

    await ayse.open();
    final dolap = await ayse.add(Roots.home, NodeKind.container, 'Dolap');
    await ayse.add(dolap.id, NodeKind.item, 'Havlu');
    final fromAyse = ayse.outgoing();

    await ali.open();
    await ali.merge(fromAyse);
    await ali.open(); // yeniden aç: veritabanından okunmalı
    expect(ali.has('Havlu'), isTrue);

    await ayse.open();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await ayse.store.deleteForever(ayse.store.search('Havlu').single.id);
    final deletion = ayse.outgoing();
    expect(deletion.tombstones, isNotEmpty, reason: 'iz ağa gitmeli');

    await ali.open();
    final stale = ali.outgoing(); // Ali'nin elinde hâlâ Havlu var
    await ali.merge(deletion);
    // Görünen bir kaydın kalıcı silinmesi otomatik kabulde de sorulur.
    expect(ali.has('Havlu'), isTrue);
    expect(ali.store.pendingGroups.single.summary.kind, ChangeKind.deleted);
    await ali.store.acceptAllChanges();
    await ali.open();
    expect(ali.has('Havlu'), isFalse);

    await ayse.open();
    await ayse.merge(stale);
    await ayse.open();
    expect(ayse.has('Havlu'), isFalse, reason: 'eski kopya silineni geri getirmemeli');
  });

  test('onaysız eşitlemede iki kişinin farklı alan değişiklikleri birlikte kalır', () async {
    final ayse = Phone('ayse', root);
    final ali = Phone('ali', root);
    await ayse.open();
    await ayse.add(Roots.home, NodeKind.item, 'Pil');
    final initial = ayse.outgoing();
    await ali.open();
    await ali.merge(initial);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    await ali.store.commit(ali.named('Pil').copyWith(name: 'Kalem pil'));
    final fromAli = ali.outgoing();

    await ayse.open();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    // Ayşe daha sonra adedi değiştirdi; eskiden kaydın tamamı onunki olurdu.
    await ayse.store.commit(ayse.named('Pil').copyWith(quantity: 8, minQuantity: 2));
    final stampBefore = ayse.stamp;
    await ayse.merge(fromAli);
    final pil = ayse.named('Kalem pil');
    expect((pil.quantity, pil.minQuantity), (8, 2));
    expect(ayse.stamp, isNot(stampBefore));

    // Ali de Ayşe'nin birleşmiş sürümünü alınca aynı yere varır.
    final merged = ayse.outgoing();
    await ali.open();
    await ali.merge(merged);
    expect(ali.named('Kalem pil').quantity, 8);
    expect(ali.stamp, stampOf(merged));

    // Yeniden açılınca grup zamanları da diskten gelir.
    await ali.open();
    expect(ali.stamp, stampOf(merged));
  });

  test('eksik resimler bildirilir, yalnızca işaret edilen resim yazılır', () async {
    final ayse = Phone('ayse', root);
    final ali = Phone('ali', root);

    await ayse.open();
    await ayse.add(Roots.home, NodeKind.container, 'Kutu', image: 'kutu.jpg');
    final state = ayse.outgoing();
    final bytes = await ayse.store.readImage('images/kutu.jpg');
    expect(bytes, isNotNull);

    await ali.open();
    await ali.merge(state);
    expect(ali.store.missingImages(), {'images/kutu.jpg'});

    // İşaret edilmeyen ya da güvensiz yollar reddedilir.
    final junk = Uint8List.fromList([1, 2, 3]);
    expect(await ali.store.saveImage('images/baska.jpg', junk), isFalse);
    expect(await ali.store.saveImage('../databases/ali.db', junk), isFalse);

    expect(await ali.store.saveImage('images/kutu.jpg', bytes!), isTrue);
    expect(ali.store.missingImages(), isEmpty);
    expect(File(p.join(ali.docs.path, 'images/kutu.jpg')).readAsStringSync(), 'foto:kutu.jpg');
  });

  test('profil resmi gibi kayda ait olmayan dosyalar karşıya verilmez', () async {
    final ayse = Phone('ayse', root);
    await ayse.open();
    File(p.join(ayse.docs.path, 'images/profil.jpg')).writeAsStringSync('yüzüm');
    expect(await ayse.store.readImage('images/profil.jpg'), isNull);
  });

  group('silmelere karşı', () {
    late Phone ayse;
    late Phone ali;

    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

    /// Ayşe'nin altı eşyası Ali'de de var (otomatik kabul).
    Future<List<Node>> six() async {
      ayse = Phone('ayse', root);
      ali = Phone('ali', root);
      await ayse.open();
      final items = [for (final name in ['A', 'B', 'C', 'D', 'E', 'F']) await ayse.add(Roots.home, NodeKind.item, name)];
      final state = ayse.outgoing();
      await ali.open();
      await ali.merge(state);
      return items;
    }

    test('otomatik kabulde tek çöpe atma gelir; toplu çöpe atma onay bekler', () async {
      final items = await six();
      await ayse.open();
      await tick();
      await ayse.store.moveToTrash(items[0].id);
      var state = ayse.outgoing();
      await ali.open();
      await ali.merge(state);
      expect(ali.store.trash.map((n) => n.name), ['A']);
      expect(ali.store.pendingCount, 0);

      await ayse.open();
      await tick();
      for (final n in items.skip(1)) {
        await ayse.store.moveToTrash(n.id);
      }
      state = ayse.outgoing();
      await ali.open();
      await ali.merge(state);
      expect(ali.store.trash.map((n) => n.name), ['A'], reason: 'beş kayıt birden: sorulur');
      expect(ali.store.pendingChanges, hasLength(5));
      await ali.store.acceptAllChanges();
      expect(ali.store.trash, hasLength(6));
    });

    test('dolu bir klasörü çöpe atmak da içindekilerle sayılır', () async {
      ayse = Phone('ayse', root);
      ali = Phone('ali', root);
      await ayse.open();
      final kutu = await ayse.add(Roots.home, NodeKind.container, 'Kutu');
      for (final name in ['A', 'B', 'C', 'D']) {
        await ayse.add(kutu.id, NodeKind.item, name);
      }
      var state = ayse.outgoing();
      await ali.open();
      await ali.merge(state);
      await ayse.open();
      await tick();
      await ayse.store.moveToTrash(kutu.id);
      state = ayse.outgoing();
      await ali.open();
      await ali.merge(state);
      expect(ali.store.trash, isEmpty);
      expect(ali.store.pendingChanges.single.nodeId, kutu.id);
    });

    test('ana kullanıcının kalıcı silmesi de onay bekler', () async {
      final items = await six();
      await ayse.open();
      await tick();
      await ayse.store.deleteForever(items[0].id);
      final state = ayse.outgoing();
      await ali.open();
      ali.store.isAdmin = (id) => id == 'ayse';
      await ali.review(state, from: 'ayse');
      expect(ali.has('A'), isTrue);
      expect(ali.store.pendingGroups.single.summary.kind, ChangeKind.deleted);
    });

    test('çöpteki kaydın kalıcı silinmesi sorulmaz; Son silinenler\'den geri gelir, karşıda da', () async {
      final items = await six();
      await ayse.open();
      await tick();
      await ayse.store.moveToTrash(items[0].id);
      var state = ayse.outgoing();
      await ali.open();
      await ali.merge(state);
      await ayse.open();
      await tick();
      await ayse.store.emptyTrash();
      expect(ayse.store.recentlyPurged.single.node.name, 'A', reason: 'kendi sildiği de arşivde');
      state = ayse.outgoing();

      await ali.open();
      await ali.merge(state);
      expect(ali.store.pendingCount, 0);
      expect(ali.store.byId(items[0].id), isNull);
      await ali.open(); // arşiv yeniden açılınca da durur
      expect(ali.store.recentlyPurged.single.node.name, 'A');
      await tick();
      await ali.store.restorePurged(items[0].id);
      expect(ali.has('A'), isTrue);
      expect(ali.store.byId(items[0].id)!.isDeleted, isFalse, reason: 'çöpe değil yerine döner');
      expect(ali.store.recentlyPurged, isEmpty);
      final back = ali.outgoing();

      await ayse.open();
      await ayse.merge(back);
      expect(ayse.has('A'), isTrue, reason: 'silme izinden yeni: karşıda da geri gelir');
    });

    test('klasörle silinenler onunla geri gelir; resmi arşivdeyken silinmez; yeri yoksa çekmeceye', () async {
      ayse = Phone('ayse', root);
      await ayse.open();
      final dolap = await ayse.add(Roots.home, NodeKind.container, 'Dolap');
      final kutu = await ayse.add(dolap.id, NodeKind.container, 'Kutu', image: 'kutu.jpg');
      await ayse.add(kutu.id, NodeKind.item, 'Vida');
      await ayse.store.deleteForever(kutu.id);
      await tick();
      await ayse.store.deleteForever(dolap.id);
      expect(File(p.join(ayse.docs.path, 'images/kutu.jpg')).existsSync(), isTrue);
      expect(ayse.store.recentlyPurged.map((r) => (r.node.name, r.inside)), [('Dolap', 0), ('Kutu', 1)]);

      await ayse.store.restorePurged(kutu.id);
      final back = ayse.named('Kutu');
      expect((back.parentId, back.inDrawer), (null, true), reason: 'Dolap hâlâ silinmiş');
      expect(ayse.store.childrenOf(back.id).map((n) => n.name), ['Vida']);
      expect(ayse.store.recentlyPurged.map((r) => r.node.name), ['Dolap']);
    });

    test('30 günü geçen arşiv düşer, resmi de silinir', () async {
      ayse = Phone('ayse', root);
      await ayse.open();
      final kutu = await ayse.add(Roots.home, NodeKind.item, 'Kutu', image: 'eski.jpg');
      await ayse.store.deleteForever(kutu.id);
      final old = DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
      await AppDatabase.instance.writeMeta(
        'purged_archive',
        jsonEncode([
          {'at': old, 'node': kutu.toMap()},
        ]),
      );
      await ayse.open();
      expect(ayse.store.recentlyPurged, isEmpty);
      expect(File(p.join(ayse.docs.path, 'images/eski.jpg')).existsSync(), isFalse);
    });

    test('kendi yedeğini içe aktarırken silmeler sorulmaz', () async {
      final items = await six();
      await ayse.open();
      await tick();
      await ayse.store.deleteForever(items[0].id);
      final state = ayse.outgoing();
      await ali.open();
      await ali.store.importBackup(nodes: state.nodes, tombstones: state.tombstones);
      expect(ali.has('A'), isFalse);
      expect(ali.store.pendingCount, 0);
    });
  });

  test('karşıdan gelen birleşme "yerel değişiklik" sayılmaz', () async {
    final ayse = Phone('ayse', root);
    final ali = Phone('ali', root);
    await ayse.open();
    await ayse.add(Roots.home, NodeKind.item, 'Şemsiye');
    final state = ayse.outgoing();

    await ali.open();
    final before = ali.store.localRevision.value;
    await ali.merge(state);
    expect(ali.store.localRevision.value, before, reason: 'yoksa iki cihaz birbirine sonsuz gönderir');
    await ali.add(Roots.home, NodeKind.item, 'Kendi eşyam');
    expect(ali.store.localRevision.value, before + 1);
  });

  group('imza', () {
    final signer = RequestSigner(RequestSigner.newKey());
    final now = DateTime.now();
    final body = utf8.encode('{"nodes":[]}');
    Map<String, String> h() => signer.headers('POST', '/state', body, now);

    bool verify({String method = 'POST', String path = '/state', List<int>? b, Map<String, String>? headers, DateTime? at, RequestSigner? by}) {
      final hs = headers ?? h();
      return (by ?? signer).verify(
        method: method,
        path: path,
        body: b ?? body,
        time: hs[RequestSigner.timeHeader],
        signature: hs[RequestSigner.signatureHeader],
        now: at ?? now,
      );
    }

    test('doğru imza geçer', () => expect(verify(), isTrue));
    test('gövdesi değiştirilmiş istek geçmez', () => expect(verify(b: utf8.encode('{"nodes":[1]}')), isFalse));
    test('başka yola taşınmış imza geçmez', () => expect(verify(path: '/image/images/a.jpg'), isFalse));
    test('başka anahtar geçmez', () => expect(verify(by: RequestSigner(RequestSigner.newKey())), isFalse));
    test('eski istek geçmez', () => expect(verify(at: now.add(const Duration(minutes: 6))), isFalse));
    test('imzasız istek geçmez', () => expect(verify(headers: const {}), isFalse));
  });

  test('klasör düzenlenince içindekiler veritabanında kalır', () async {
    final ayse = Phone('ayse', root);
    await ayse.open();
    final dolap = await ayse.add(Roots.home, NodeKind.container, 'Dolap');
    await ayse.add(dolap.id, NodeKind.item, 'Havlu');
    await ayse.store.commit(ayse.named('Dolap').copyWith(name: 'Gardırop'));
    await ayse.store.move(dolap.id, Roots.drawer);
    await ayse.open();
    expect(ayse.store.pathLabel(ayse.named('Havlu').id), 'Çekmece / Gardırop');
  });

  group('bekleyen değişiklikler', () {
    late Phone ayse;
    late Phone ali;

    /// Ayşe'nin Mutfak/Tencere'si iki telefonda da var.
    Future<void> shared() async {
      ayse = Phone('ayse', root);
      ali = Phone('ali', root);
      await ayse.open();
      final mutfak = await ayse.add(Roots.home, NodeKind.container, 'Mutfak');
      await ayse.add(Roots.home, NodeKind.container, 'Balkon');
      await ayse.add(mutfak.id, NodeKind.item, 'Tencere');
      final initial = ayse.outgoing();
      await ali.open();
      await ali.merge(initial);
    }

    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

    test('karşının değişikliği hemen uygulanmaz, kabul edilince uygulanır', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.store.move(ayse.named('Tencere').id, ayse.named('Balkon').id);
      final moved = ayse.outgoing();

      await ali.open();
      await ali.review(moved);
      final tencere = ali.named('Tencere');
      expect(ali.store.pathLabel(tencere.id), 'Ana ekran / Mutfak', reason: 'henüz yerinde');
      expect(ali.store.pendingCount, 1);
      final group = ali.store.pendingGroups.single;
      expect(group.summary.kind, ChangeKind.moved);
      expect(group.lead.author, 'ayse', reason: 'değişikliği yapan');
      expect(ali.store.hasPendingMark(tencere.id), isTrue);
      expect(ali.store.hasPendingMark(ali.named('Mutfak').id), isTrue);

      // Aynı durum tekrar gelince (her eşitlemede gelir) çoğalmaz.
      await ali.review(moved);
      expect(ali.store.pendingCount, 1);

      await ali.open(); // bekleyenler uygulama kapanınca kaybolmaz
      expect(ali.store.pendingCount, 1);

      await ali.store.acceptAllChanges();
      expect(ali.store.pathLabel(tencere.id), 'Ana ekran / Balkon');
      expect(ali.store.pendingCount, 0);
      await ali.open();
      expect(ali.store.pendingCount, 0);
      expect(ali.store.pathLabel(tencere.id), 'Ana ekran / Balkon');
    });

    test('reddedilen değişiklikte bizim sürüm kalır ve karşıya da gider', () async {
      await shared();
      await ayse.open();
      await tick();
      final t = ayse.named('Tencere');
      await ayse.store.commit(t.copyWith(name: 'Düdüklü'));
      final renamed = ayse.outgoing();

      await ali.open();
      await ali.review(renamed);
      final group = ali.store.pendingGroups.single;
      expect(group.summary.renamed, isTrue);
      expect(group.summary.newName, 'Düdüklü');
      await tick();
      await ali.store.rejectChanges(group.nodeIds);
      expect(ali.store.pendingCount, 0);
      expect(ali.has('Tencere'), isTrue);
      final back = ali.outgoing();

      await ayse.open();
      await ayse.review(back);
      expect(ayse.store.pendingGroups.single.summary.newName, 'Tencere',
          reason: 'ret karşıda yeni bir değişiklik olarak görünür');
    });

    test('yeni klasör ve içindekiler tek satırda; biri kabul edilince zinciri gelir', () async {
      await shared();
      await ayse.open();
      await tick();
      final kutu = await ayse.add(Roots.home, NodeKind.container, 'Kutu');
      final ic = await ayse.add(kutu.id, NodeKind.container, 'Poşet');
      final pil = await ayse.add(ic.id, NodeKind.item, 'Pil');
      final state = ayse.outgoing();

      await ali.open();
      await ali.review(state);
      expect(ali.store.pendingCount, 1);
      final group = ali.store.pendingGroups.single;
      expect(group.lead.nodeId, kutu.id);
      expect(group.extra, 2);
      expect(group.summary.kind, ChangeKind.added);

      await ali.store.acceptChanges([pil.id]);
      expect(ali.store.pathLabel(pil.id), 'Ana ekran / Kutu / Poşet');
      expect(ali.store.pendingCount, 0);
    });

    test('reddedilen ekleme çöpe gider', () async {
      await shared();
      await ayse.open();
      await tick();
      final kutu = await ayse.add(Roots.home, NodeKind.container, 'Kutu');
      await ayse.add(kutu.id, NodeKind.item, 'Pil');
      final state = ayse.outgoing();

      await ali.open();
      await ali.review(state);
      await ali.store.rejectAllChanges();
      expect(ali.store.pendingCount, 0);
      expect(ali.store.childrenOf(Roots.home).map((n) => n.name), isNot(contains('Kutu')));
      expect(ali.store.trash.map((n) => n.name), ['Kutu']);
      final back = ali.outgoing();
      expect(back.nodes[kutu.id]!.isDeleted, isTrue);
    });

    test('kalıcı silme de onay bekler', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.store.deleteForever(ayse.named('Balkon').id);
      final state = ayse.outgoing();

      await ali.open();
      await ali.review(state);
      expect(ali.has('Balkon'), isTrue);
      expect(ali.store.pendingGroups.single.summary.kind, ChangeKind.deleted);
      await ali.store.acceptAllChanges();
      expect(ali.has('Balkon'), isFalse);
    });

    test('bizde sonradan aynı alanı düzenlenen kaydın bekleyen değişikliği düşer', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.named('Tencere').copyWith(note: 'kapağı yok'));
      final state = ayse.outgoing();

      await ali.open();
      await ali.review(state);
      expect(ali.store.pendingCount, 1);
      await tick();
      // Başka bir alan: bekleyen not değişikliği durur, yalnızca notu gösterir.
      await ali.store.commit(ali.named('Tencere').copyWith(name: 'Tava'));
      expect(ali.store.pendingCount, 1);
      final sum = ali.store.pendingGroups.single.summary;
      expect(sum.noteChanged, isTrue);
      expect(sum.renamed, isFalse, reason: 'ad bizim değişikliğimiz, karşıdan gelmiyor');
      await tick();
      await ali.store.commit(ali.named('Tava').copyWith(note: 'kapak dolapta'));
      expect(ali.store.pendingCount, 0);
    });

    test('kabul edilen değişiklik bizim başka alandaki değişikliğimizi ezmez', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.named('Tencere').copyWith(quantity: 2));
      final state = ayse.outgoing();

      await ali.open();
      await tick();
      await ali.store.commit(ali.named('Tencere').copyWith(name: 'Tava'));
      await ali.review(state);
      expect(ali.store.pendingGroups.single.summary.quantityChanged, isTrue);
      await ali.store.acceptAllChanges();
      final tava = ali.named('Tava');
      expect(tava.quantity, 2);

      // Ayşe de Ali'nin adını alır, adedini kaybetmez; iki taraf aynı yere varır.
      final back = ali.outgoing();
      await ayse.open();
      await ayse.merge(back);
      expect(ayse.named('Tava').quantity, 2);
      expect(ayse.stamp, ali.stamp);
    });

    test('ret yalnızca reddedilen alanı geri çevirir; karşıya bizimki gider', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.named('Tencere').copyWith(note: 'kapağı yok'));
      final state = ayse.outgoing();

      await ali.open();
      await ali.review(state);
      await ali.store.rejectAllChanges();
      expect(ali.named('Tencere').note ?? '', '');
      final back = ali.outgoing();

      // Ayşe bu arada adedi değiştirmişti: o kalır, not Ali'nin (boş) notuna döner.
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.named('Tencere').copyWith(quantity: 5));
      await ayse.merge(back);
      final t = ayse.named('Tencere');
      expect(t.note ?? '', '');
      expect(t.quantity, 5);
    });

    test('ekler tek tek birleşir: iki tarafın eklediği kalır; reddedilen ek karşıda da kalkar', () async {
      await shared();
      Attachment link(String id) =>
          Attachment(id: id, name: id, addedAt: DateTime.now(), url: 'https://ornek.com/$id');
      List<String> names(Node n) => [for (final a in n.attachments) a.name];

      // İkisi de aynı tencereye ayrı ayrı ek koyar.
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.named('Tencere').copyWith(attachments: [link('kilavuz')]));
      final fromAyse = ayse.outgoing();
      await ali.open();
      await tick();
      await ali.store.commit(ali.named('Tencere').copyWith(attachments: [link('garanti')]));

      // Ali kabul eder: kendi eki de durur (eskiden son yazanın listesi kalırdı).
      await ali.review(fromAyse);
      expect(ali.store.pendingGroups.single.summary.attachmentsChanged, isTrue);
      await ali.store.acceptAllChanges();
      expect(names(ali.named('Tencere')), ['kilavuz', 'garanti']);
      final fromAli = ali.outgoing();
      await ayse.open();
      await ayse.merge(fromAli);
      expect(names(ayse.named('Tencere')), ['kilavuz', 'garanti']);
      expect(ayse.stamp, ali.stamp);

      // Ayşe bir ek daha koyar; Ali bu kez reddeder: ek Ayşe'de de kalkar,
      // öteki ikisi yerinde durur.
      await tick();
      await ayse.store.commit(
        ayse.named('Tencere').copyWith(attachments: [...ayse.named('Tencere').attachments, link('video')]),
      );
      final again = ayse.outgoing();
      await ali.open();
      await ali.review(again);
      await ali.store.rejectAllChanges();
      expect(names(ali.named('Tencere')), ['kilavuz', 'garanti']);
      final back = ali.outgoing();
      await ayse.open();
      await ayse.merge(back);
      expect(names(ayse.named('Tencere')), ['kilavuz', 'garanti']);
      expect(ayse.named('Tencere').attachmentTombs.keys, ['video']);
      expect(ayse.stamp, ali.stamp);
    });

    test('karşı taraf bizim yeni değişikliğimizi birleştirdiyse bekleyen kısım onun adına yazılır', () async {
      await shared();
      final id = ayse.named('Tencere').id;
      await ali.open();
      await tick();
      await ali.store.commit(ali.named('Tencere').copyWith(name: 'Tava'));
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.named('Tencere').copyWith(quantity: 2));
      final fromAyse = ayse.outgoing();

      // Ali, Ayşe'nin daha yeni adet değişikliğini alır; kaydın son yazarı Ayşe olur.
      await ali.open();
      await ali.merge(fromAyse);
      final back = ali.outgoing();
      expect(back.nodes[id]!.updatedBy, 'ayse');

      await ayse.open();
      await ayse.review(back, from: 'ali');
      expect(ayse.store.pendingChanges.single.author, 'ali');
      final sum = ayse.store.pendingGroups.single.summary;
      expect((sum.renamed, sum.quantityChanged), (true, false));
      await ayse.open(); // diskten okununca da
      expect(ayse.store.pendingChanges.single.author, 'ali');
    });

    test('aynı kayda gelen iki değişiklik tek satırda birleşir', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.named('Tencere').copyWith(note: 'kapağı yok'));
      final first = ayse.outgoing();
      await tick();
      await ayse.store.commit(ayse.named('Tencere').copyWith(quantity: 3));
      final second = ayse.outgoing();

      await ali.open();
      await ali.review(first);
      await ali.review(second);
      await ali.review(first); // eski sürüm yeniden gelse de bir şey kaybolmaz
      expect(ali.store.pendingCount, 1);
      final sum = ali.store.pendingGroups.single.summary;
      expect(sum.noteChanged && sum.quantityChanged, isTrue);
      await ali.store.acceptAllChanges();
      final t = ali.named('Tencere');
      expect((t.note, t.quantity), ('kapağı yok', 3));
    });

    test('yalnızca zamanı değişen kayıt sessizce alınır', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.named('Tencere')); // değişiklik yapmadan kaydet
      final state = ayse.outgoing();

      await ali.open();
      await ali.review(state);
      expect(ali.store.pendingCount, 0);
    });

    test('sıralama değişiklikleri aynı yerde tek satır', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.store.reorder(Roots.home, 0, 1);
      final state = ayse.outgoing();

      await ali.open();
      await ali.review(state);
      expect(ali.store.pendingCount, 1);
      expect(ali.store.pendingGroups.single.summary.kind, ChangeKind.reordered);
      await ali.store.acceptAllChanges();
      expect(ali.store.childrenOf(Roots.home).map((n) => n.name), ['Balkon', 'Mutfak']);
    });

    test('bekleyen eklemenin resmi onaydan önce alınabilir', () async {
      await shared();
      await ayse.open();
      await tick();
      await ayse.add(Roots.home, NodeKind.item, 'Lamba', image: 'lamba.jpg');
      final state = ayse.outgoing();
      final bytes = await ayse.store.readImage('images/lamba.jpg');

      await ali.open();
      await ali.review(state);
      expect(ali.store.missingImages(), {'images/lamba.jpg'});
      expect(await ali.store.saveImage('images/lamba.jpg', bytes!), isTrue);
      await ali.store.rejectAllChanges();
      // Çöpe giden kayıt hâlâ resmini kullanıyor.
      expect(File(p.join(ali.docs.path, 'images/lamba.jpg')).existsSync(), isTrue);
    });
  });

  group('kayıp çekmecesi', () {
    test('yerinde olmayan eşya kayba alınır, son yeri saklanır, yeniden açılınca durur', () async {
      final ayse = Phone('ayse', root);
      await ayse.open();
      final mutfak = await ayse.add(Roots.home, NodeKind.container, 'Mutfak');
      final tencere = await ayse.add(mutfak.id, NodeKind.item, 'Tencere');

      expect(await ayse.store.markLost(tencere.id), isTrue);
      expect(ayse.store.childrenOf(mutfak.id), isEmpty);
      expect(ayse.store.childrenOf(Roots.lost).single.id, tencere.id);
      expect(ayse.store.childrenOf(Roots.home).map((n) => n.name), ['Mutfak'],
          reason: 'kayıp eşya ana ekranda görünmez');
      expect(ayse.store.pathLabel(tencere.id), 'Kayıp');
      expect(ayse.store.lastSeenLabel(ayse.store.byId(tencere.id)!), 'Ana ekran / Mutfak');
      expect(ayse.store.visibleRecordCount, 2);

      await ayse.open();
      expect(ayse.store.childrenOf(Roots.lost).single.id, tencere.id);

      // Yerini bilen bir yere koyunca bulunmuş olur.
      final balkon = await ayse.add(Roots.home, NodeKind.container, 'Balkon');
      expect(await ayse.store.move(tencere.id, balkon.id), isTrue);
      final found = ayse.store.byId(tencere.id)!;
      expect(found.isLost, isFalse);
      expect(found.lostFrom, isNull);
      expect(ayse.store.childrenOf(Roots.lost), isEmpty);
    });

    test('sürükleyip kayıp çekmecesine bırakmak da kayıp bildirir', () async {
      final ayse = Phone('ayse', root);
      await ayse.open();
      final kutu = await ayse.add(Roots.home, NodeKind.container, 'Kutu');
      expect(ayse.store.canMove(kutu.id, Roots.lost), isTrue);
      await ayse.store.move(kutu.id, Roots.lost);
      expect(ayse.store.byId(kutu.id)!.isLost, isTrue);
      expect(ayse.store.canMove(kutu.id, Roots.lost), isFalse, reason: 'zaten kayıp');
    });

    test('düzenleyiciden yer verilen kayıp eşya bulunmuş sayılır', () async {
      final ayse = Phone('ayse', root);
      await ayse.open();
      final kutu = await ayse.add(Roots.home, NodeKind.container, 'Kutu');
      final pil = await ayse.add(Roots.home, NodeKind.item, 'Pil');
      await ayse.store.markLost(pil.id);
      await ayse.store.commit(ayse.store.byId(pil.id)!.copyWith(parentId: kutu.id));
      expect(ayse.store.byId(pil.id)!.isLost, isFalse);
    });

    /// Ayşe'nin Mutfak/Tencere'si ve boş Balkon'u iki telefonda da var;
    /// Ayşe tencereyi kayıp bildirmiş, Ali'ye ulaşmış.
    Future<(Phone, Phone, Node, Node)> lostShared() async {
      final ayse = Phone('ayse', root);
      final ali = Phone('ali', root);
      await ayse.open();
      final mutfak = await ayse.add(Roots.home, NodeKind.container, 'Mutfak');
      final balkon = await ayse.add(Roots.home, NodeKind.container, 'Balkon');
      final tencere = await ayse.add(mutfak.id, NodeKind.item, 'Tencere');
      final initial = ayse.outgoing();
      await ali.open();
      await ali.merge(initial);
      await ayse.open();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await ayse.store.markLost(tencere.id);
      final lostState = ayse.outgoing();
      await ali.open();
      await ali.review(lostState);
      return (ayse, ali, tencere, balkon);
    }

    Future<List<LostEvent>> collect(Phone p, Future<void> Function() body) async {
      final events = <LostEvent>[];
      final sub = p.store.lostEvents.listen(events.add);
      await body();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      return events;
    }

    test('kayıp bildirimi onay beklemeden gelir ve haber olarak duyurulur', () async {
      final ayse = Phone('ayse', root);
      final ali = Phone('ali', root);
      await ayse.open();
      final mutfak = await ayse.add(Roots.home, NodeKind.container, 'Mutfak');
      final tencere = await ayse.add(mutfak.id, NodeKind.item, 'Tencere');
      final initial = ayse.outgoing();
      await ali.open();
      await ali.merge(initial);
      await ayse.open();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await ayse.store.markLost(tencere.id);
      final lostState = ayse.outgoing();

      await ali.open();
      final events = await collect(ali, () => ali.review(lostState));
      expect(ali.store.pendingCount, 0, reason: 'kayıp bildirimi onaya düşmez');
      expect(ali.store.childrenOf(Roots.lost).single.id, tencere.id);
      expect(events.single.found, isFalse);
      expect(events.single.by, 'ayse');
    });

    test('yerini bilen bildirir; bulunma da onaysız gelir', () async {
      final (ayse, ali, tencere, balkon) = await lostShared();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await ali.store.move(tencere.id, balkon.id);
      final foundState = ali.outgoing();

      await ayse.open();
      final events = await collect(ayse, () => ayse.review(foundState));
      expect(events.single.found, isTrue);
      expect(ayse.store.pendingCount, 0);
      expect(ayse.store.childrenOf(Roots.lost), isEmpty);
      expect(ayse.store.pathLabel(tencere.id), 'Ana ekran / Balkon');
    });

    test('yeni bir klasöre konan bulunmuş eşya, klasörle birlikte onaya düşer', () async {
      final (ayse, ali, tencere, _) = await lostShared();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final dolap = await ali.add(Roots.home, NodeKind.container, 'Dolap');
      await ali.store.move(tencere.id, dolap.id);
      final foundState = ali.outgoing();

      await ayse.open();
      await ayse.review(foundState);
      expect(ayse.store.byId(tencere.id)!.isLost, isTrue, reason: 'yersiz kalmasın diye bekler');
      final kinds = ayse.store.pendingGroups.map((g) => g.summary.kind).toSet();
      expect(kinds, {ChangeKind.added, ChangeKind.found});
      final found = ayse.store.pendingGroups.firstWhere((g) => g.summary.kind == ChangeKind.found);
      await ayse.store.acceptChanges(found.nodeIds);
      expect(ayse.store.pathLabel(tencere.id), 'Ana ekran / Dolap', reason: 'klasör de gelir');
      expect(ayse.store.pendingCount, 0);
    });

    test('kendi kayıp bildirimim bana haber olarak dönmez', () async {
      final ayse = Phone('ayse', root);
      await ayse.open();
      final pil = await ayse.add(Roots.home, NodeKind.item, 'Pil');
      final events = <LostEvent>[];
      final sub = ayse.store.lostEvents.listen(events.add);
      await ayse.store.markLost(pil.id);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(events, isEmpty);
    });
  });

  group('ana kullanıcı ve sorumlu', () {
    late Phone ayse;
    late Phone ali;

    /// Ayşe'nin Mutfak/Tencere ve Garaj/Matkap'ı iki telefonda da var;
    /// Ali'nin telefonu değişiklikleri onayla alıyor.
    Future<(Node mutfak, Node tencere, Node matkap)> shared({List<String> mutfakManagers = const []}) async {
      ayse = Phone('ayse', root);
      ali = Phone('ali', root);
      await ayse.open();
      final mutfak = await ayse.add(Roots.home, NodeKind.container, 'Mutfak');
      if (mutfakManagers.isNotEmpty) {
        await ayse.store.commit(ayse.store.byId(mutfak.id)!.copyWith(managers: mutfakManagers));
      }
      final garaj = await ayse.add(Roots.home, NodeKind.container, 'Garaj');
      final tencere = await ayse.add(mutfak.id, NodeKind.item, 'Tencere');
      final matkap = await ayse.add(garaj.id, NodeKind.item, 'Matkap');
      final initial = ayse.outgoing();
      await ali.open();
      await ali.merge(initial);
      return (mutfak, tencere, matkap);
    }

    Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 5));

    test('ana kullanıcının değişikliği onaysız uygulanır ve duyurulur', () async {
      final (_, tencere, _) = await shared();
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.store.byId(tencere.id)!.copyWith(name: 'Düdüklü'));
      final state = ayse.outgoing();

      await ali.open();
      ali.store.isAdmin = (id) => id == 'ayse';
      final events = <AuthorityEvent>[];
      final sub = ali.store.authorityEvents.listen(events.add);
      await ali.review(state);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(ali.store.pendingCount, 0);
      expect(ali.has('Düdüklü'), isTrue);
      expect(events.single.author, 'ayse');
      expect(events.single.count, 1);
    });

    test('sorumlu kendi klasöründe onaysız, başka yerde onayla', () async {
      final (_, tencere, matkap) = await shared(mutfakManagers: ['ayse']);
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.store.byId(tencere.id)!.copyWith(name: 'Düdüklü'));
      await ayse.store.commit(ayse.store.byId(matkap.id)!.copyWith(name: 'Şarjlı matkap'));
      final state = ayse.outgoing();

      await ali.open();
      ali.store.isAdmin = (_) => false; // Ayşe burada ana kullanıcı değil
      expect(ali.store.managersOf(tencere.id), {'ayse'});
      await ali.review(state);
      expect(ali.has('Düdüklü'), isTrue, reason: 'Mutfak Ayşe\'nin sorumluluğunda');
      expect(ali.has('Şarjlı matkap'), isFalse, reason: 'Garaj değil');
      expect(ali.store.pendingGroups.single.lead.nodeId, matkap.id);
    });

    test('güvenilen kişinin değişikliği sormadan gelir; kalıcı silmesi yine sorulur', () async {
      final (_, tencere, matkap) = await shared();
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.store.byId(tencere.id)!.copyWith(name: 'Düdüklü'));
      await ayse.store.deleteForever(matkap.id);
      final state = ayse.outgoing();

      await ali.open();
      ali.store.isTrusted = (id) => id == 'ayse';
      await ali.review(state);
      expect(ali.has('Düdüklü'), isTrue);
      expect(ali.has('Matkap'), isTrue);
      expect(ali.store.pendingGroups.single.summary.kind, ChangeKind.deleted);
    });

    test('adet ve alışveriş listesi sormadan gelir; ad değişikliği sorulur', () async {
      final (_, tencere, matkap) = await shared();
      await ayse.open();
      await tick();
      await ayse.store.setQuantity(tencere.id, 3);
      await ayse.store.setWanted(matkap.id, true);
      await ayse.store.commit(ayse.store.byId(tencere.id)!.copyWith(name: 'Düdüklü'));
      var state = ayse.outgoing();

      await ali.open();
      ali.store.acceptsSmall = () => true;
      await ali.review(state);
      expect(ali.store.byId(matkap.id)!.isWanted, isTrue);
      expect(ali.store.byId(tencere.id)!.quantity, isNull, reason: 'aynı kayıtta ad da değişti: birlikte sorulur');
      expect(ali.store.pendingCount, 1);

      await ayse.open();
      await tick();
      await ayse.store.setQuantity(matkap.id, 2);
      state = ayse.outgoing();
      await ali.open();
      ali.store.acceptsSmall = () => false;
      await ali.review(state);
      expect(ali.store.byId(matkap.id)!.quantity, isNull, reason: 'ayar kapalı: sorulur');
    });

    test('geri çevrilen değişikliğin haberi yapana gider', () async {
      final (_, tencere, _) = await shared();
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.store.byId(tencere.id)!.copyWith(name: 'Düdüklü'));
      final state = ayse.outgoing();

      await ali.open();
      final sent = <Notice>[];
      ali.store.onRejected = sent.addAll;
      await ali.review(state);
      await ali.store.rejectAllChanges();
      expect(sent.single.to, 'ayse');
      expect(sent.single.by, 'ali');
      expect(sent.single.kind, 'edited');
      expect(sent.single.name, 'Tencere');
    });

    test('sorumlu olmayanın değişikliği onaya düşer', () async {
      final (_, tencere, _) = await shared(mutfakManagers: ['veli']);
      await ayse.open();
      await tick();
      await ayse.store.commit(ayse.store.byId(tencere.id)!.copyWith(name: 'Düdüklü'));
      final state = ayse.outgoing();
      await ali.open();
      ali.store.isAdmin = (_) => false;
      await ali.review(state);
      expect(ali.store.pendingCount, 1);
      expect(ali.has('Düdüklü'), isFalse);
    });

    test('sorumlular kayıtla saklanır ve eşitlenir', () async {
      final (mutfak, _, _) = await shared(mutfakManagers: ['ayse', 'veli']);
      await ali.open();
      expect(ali.store.byId(mutfak.id)!.managers, ['ayse', 'veli']);
      final back = SyncState.fromJson(jsonDecode(jsonEncode(ali.outgoing().toJson())));
      expect(back.nodes[mutfak.id]!.managers, ['ayse', 'veli']);
    });
  });

  group('adet', () {
    test('adet 0 olunca kayıt silinmez, yeri durur; yeniden açınca ve eşitlenince korunur', () async {
      final ayse = Phone('ayse', root);
      final ali = Phone('ali', root);
      await ayse.open();
      final dolap = await ayse.add(Roots.home, NodeKind.container, 'Dolap');
      final pil = await ayse.add(dolap.id, NodeKind.item, 'Pil');
      await ayse.store.setQuantity(pil.id, 2);
      await ayse.store.setQuantity(pil.id, 1);
      await ayse.store.setQuantity(pil.id, 0);
      await ayse.store.setQuantity(pil.id, -3); // 0'ın altına inmez
      expect(ayse.store.byId(pil.id)!.quantity, 0);
      expect(ayse.store.pathLabel(pil.id), 'Ana ekran / Dolap', reason: 'tükenince yeri durur');

      await ayse.open();
      expect(ayse.store.byId(pil.id)!.quantity, 0);
      final state = ayse.outgoing();

      await ali.open();
      await ali.merge(state);
      expect(ali.store.byId(pil.id)!.quantity, 0);

      // Stok gelince aynı kayıttan artar; karşıda onaya "adet" değişikliği düşer.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await ali.store.setQuantity(pil.id, 12);
      final restocked = ali.outgoing();
      await ayse.open();
      await ayse.review(restocked);
      final change = ayse.store.pendingGroups.single;
      expect(change.summary.quantityChanged, isTrue);
      expect(change.summary.kind, ChangeKind.edited);
      await ayse.store.acceptAllChanges();
      expect(ayse.store.byId(pil.id)!.quantity, 12);
    });

    test('dışarıdan gelen geçersiz adet düşürülür', () {
      final ok = sanitizeNode({'id': 'a', 'kind': 'item', 'name': 'x', 'color': 1, 'quantity': 3});
      final bad = sanitizeNode({'id': 'b', 'kind': 'item', 'name': 'x', 'color': 1, 'quantity': -4});
      final odd = sanitizeNode({'id': 'c', 'kind': 'item', 'name': 'x', 'color': 1, 'quantity': 'çok'});
      expect(ok!.quantity, 3);
      expect(bad!.quantity, isNull);
      expect(odd!.quantity, isNull);
    });
  });
}
