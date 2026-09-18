import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/lots.dart';
import 'package:envanter/core/text_match.dart';
import 'package:envanter/core/time_span.dart';
import 'package:envanter/data/settings.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ağaç mantığı uygulamanın kalbi: döngü engelleme, varsayılan adlar,
/// yumuşak silme ve yol hesabı burada doğrulanıyor.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppPaths.useDirectory(Directory.systemTemp.createTempSync('envanter_test').path);
  });

  late InventoryStore store;

  setUp(() async {
    // Her test kendi bellek içi veritabanıyla başlasın.
    await AppDatabase.instance.openForTest(inMemory: true);
    store = InventoryStore();
    await store.init();
    // Yol etiketleri dile bağlı; test makinesinin diline göre değişmesin.
    await store.updateSettings(
      store.settings.copyWith(language: AppLanguage.turkish),
    );
  });

  tearDown(() async => AppDatabase.instance.close());

  Future<Node> add(String parent, NodeKind kind, [String? name]) async {
    var draft = store.draft(parentId: parent, kind: kind);
    if (name != null) draft = draft.copyWith(name: name);
    await store.commit(draft);
    return store.byId(draft.id)!;
  }

  group('varsayılan ad', () {
    test('klasörler 1, 2, 3 diye ilerler', () async {
      final a = await add(Roots.home, NodeKind.container);
      final b = await add(Roots.home, NodeKind.container);
      final c = await add(Roots.home, NodeKind.container);
      expect([a.name, b.name, c.name], ['1', '2', '3']);
    });

    test('aradan biri silinince boşalan sayı yeniden kullanılır', () async {
      await add(Roots.home, NodeKind.container); // 1
      final two = await add(Roots.home, NodeKind.container); // 2
      await add(Roots.home, NodeKind.container); // 3
      await store.moveToTrash(two.id);

      final next = await add(Roots.home, NodeKind.container);
      expect(next.name, '2');
    });

    test('sayma her seviyede kendi içinde başlar', () async {
      final box = await add(Roots.home, NodeKind.container); // "1"
      final inner = await add(box.id, NodeKind.container);
      expect(inner.name, '1');
    });

    test('adsız kaydedilen eşya numaralanır; silinenin numarası yeniden kullanılır', () async {
      expect(store.draft(parentId: Roots.home, kind: NodeKind.item).name, isEmpty, reason: 'taslak boş başlar');
      final a = await add(Roots.home, NodeKind.item);
      final b = await add(Roots.home, NodeKind.item);
      final box = await add(Roots.home, NodeKind.container);
      final c = await add(box.id, NodeKind.item);
      expect([a.name, b.name, c.name], ['Adsız 1', 'Adsız 2', 'Adsız 3'], reason: 'envanter genelinde');
      await store.moveToTrash(b.id);
      expect((await add(Roots.home, NodeKind.item)).name, 'Adsız 2');
      expect((await add(Roots.home, NodeKind.item)).name, 'Adsız 4');
      // Adı silinen eşya da numara alır.
      await store.commit(store.byId(a.id)!.copyWith(name: '  '));
      expect(store.byId(a.id)!.name, 'Adsız 1');
    });

    test('çöpten geri gelen "Adsız N" numarası alınmışsa yeni numara alır', () async {
      final a = await add(Roots.home, NodeKind.item);
      await store.moveToTrash(a.id);
      final b = await add(Roots.home, NodeKind.item);
      expect(b.name, 'Adsız 1', reason: 'boşalan numara');
      await store.restore(a.id);
      expect(store.byId(a.id)!.name, 'Adsız 2');
      // Kalıcı silinip geri getirilen de.
      await store.deleteForever(b.id);
      final c = await add(Roots.home, NodeKind.item);
      expect(c.name, 'Adsız 1');
      await store.restorePurged(b.id);
      expect(store.byId(b.id)!.name, 'Adsız 3');
    });
  });

  test('aynı seviyedeki kartlar farklı renk alır', () async {
    final a = await add(Roots.home, NodeKind.container);
    final b = await add(Roots.home, NodeKind.container);
    final c = await add(Roots.home, NodeKind.container);
    expect({a.color, b.color, c.color}.length, 3);
  });

  group('taşıma', () {
    test('klasör kendi içine taşınamaz', () async {
      final outer = await add(Roots.home, NodeKind.container, 'Dolap');
      final inner = await add(outer.id, NodeKind.container, 'Raf');

      expect(store.canMove(outer.id, inner.id), isFalse);
      expect(await store.move(outer.id, inner.id), isFalse);
      expect(store.byId(outer.id)!.parentId, isNull);
    });

    test('kart kendi üzerine taşınamaz', () async {
      final box = await add(Roots.home, NodeKind.container);
      expect(store.canMove(box.id, box.id), isFalse);
    });

    test('zaten bulunduğu yere taşıma reddedilir', () async {
      final box = await add(Roots.home, NodeKind.container);
      final item = await add(box.id, NodeKind.item, 'Çekiç');
      expect(store.canMove(item.id, box.id), isFalse);
      expect(store.canMove(item.id, Roots.home), isTrue);
    });

    test('çekmeceye ve köke taşıma çalışır', () async {
      final box = await add(Roots.home, NodeKind.container, 'Kutu');
      final item = await add(box.id, NodeKind.item, 'Makas');

      expect(await store.move(item.id, Roots.drawer), isTrue);
      expect(store.childrenOf(Roots.drawer).map((n) => n.id), [item.id]);
      expect(store.byId(item.id)!.inDrawer, isTrue);

      expect(await store.move(item.id, Roots.home), isTrue);
      expect(store.byId(item.id)!.inDrawer, isFalse);
      expect(store.childrenOf(Roots.home).length, 2);
    });
  });

  group('çöp kutusu', () {
    test('klasör silinince içindekiler de görünmez olur', () async {
      final box = await add(Roots.home, NodeKind.container, 'Sandık');
      final item = await add(box.id, NodeKind.item, 'Battaniye');

      await store.moveToTrash(box.id);

      expect(store.childrenOf(Roots.home), isEmpty);
      // Alt ağaç ayrıca işaretlenmez; atası çöpte olduğu için gizlidir.
      expect(store.byId(item.id)!.isDeleted, isFalse);
      expect(store.trash.map((n) => n.id), [box.id]);
      expect(store.descendantCount(box.id), 1);
    });

    test('geri alınca alt ağaç birlikte döner', () async {
      final box = await add(Roots.home, NodeKind.container, 'Sandık');
      final item = await add(box.id, NodeKind.item, 'Battaniye');

      await store.moveToTrash(box.id);
      await store.restore(box.id);

      expect(store.childrenOf(Roots.home).map((n) => n.id), [box.id]);
      expect(store.childrenOf(box.id).map((n) => n.id), [item.id]);
    });

    test('üstü hâlâ çöpteyken geri alınan kayıt çekmeceye düşer', () async {
      final box = await add(Roots.home, NodeKind.container, 'Sandık');
      final item = await add(box.id, NodeKind.item, 'Battaniye');

      await store.moveToTrash(item.id);
      await store.moveToTrash(box.id);
      // Yalnızca eşya geri alınırsa döneceği klasör hâlâ çöpte; kayıp
      // olmasın diye çekmeceye alınıyor.
      await store.restore(item.id);

      final restored = store.byId(item.id)!;
      expect(restored.inDrawer, isTrue);
      expect(restored.parentId, isNull);
      expect(store.childrenOf(Roots.drawer).map((n) => n.id), [item.id]);
    });

    test('üstünün üstü çöpteyse de geri gelen eşya çekmeceye döner, görünmez kalmaz', () async {
      final garage = await add(Roots.home, NodeKind.container, 'Garaj');
      final shelf = await add(garage.id, NodeKind.container, 'Raf');
      final item = await add(shelf.id, NodeKind.item, 'Matkap');

      await store.moveToTrash(item.id);
      await store.moveToTrash(garage.id);
      // Raf silinmiş değil ama çöpteki Garaj'ın altında: eşya orada "geri gelse" çöp
      // listesinden çıkar, hiçbir yerde de görünmezdi.
      await store.restore(item.id);

      final restored = store.byId(item.id)!;
      expect(store.isLive(restored), isTrue);
      expect(restored.inDrawer, isTrue);
      expect(restored.parentId, isNull);
      expect(store.trash.map((n) => n.id), [garage.id]);
    });

    test('klasör kalıcı silinince çöpteki çocukları da gider', () async {
      final box = await add(Roots.home, NodeKind.container, 'Sandık');
      final item = await add(box.id, NodeKind.item, 'Battaniye');

      await store.moveToTrash(item.id);
      await store.deleteForever(box.id);

      expect(store.byId(item.id), isNull);
      expect(store.trash, isEmpty);
    });

    test('kalıcı silme alt ağacı da temizler', () async {
      final box = await add(Roots.home, NodeKind.container, 'Sandık');
      final item = await add(box.id, NodeKind.item, 'Battaniye');

      await store.deleteForever(box.id);

      expect(store.byId(box.id), isNull);
      expect(store.byId(item.id), isNull);
    });
  });

  group('yol ve arama', () {
    test('pathLabel köke kadar olan zinciri verir', () async {
      final kitchen = await add(Roots.home, NodeKind.container, 'Mutfak');
      final shelf = await add(kitchen.id, NodeKind.container, 'Üst dolap');
      final item = await add(shelf.id, NodeKind.item, 'Tencere');

      expect(store.pathLabel(kitchen.id), 'Ana ekran');
      expect(store.pathLabel(item.id), 'Ana ekran / Mutfak / Üst dolap');
    });

    test('kaydedilmemiş taslak da yolunu bilir', () async {
      final kitchen = await add(Roots.home, NodeKind.container, 'Mutfak');
      final draft = store.draft(parentId: kitchen.id, kind: NodeKind.item);

      expect(store.byId(draft.id), isNull);
      expect(
        store.pathLabelForParent(draft.parentId, inDrawer: draft.inDrawer),
        'Ana ekran / Mutfak',
      );
    });

    test('arama ad, konum adı ve notta geçer, çöpteki gelmez', () async {
      final box = await add(Roots.home, NodeKind.container, 'Garaj');
      final drill = await add(box.id, NodeKind.item, 'Matkap');
      await store.commit(drill.copyWith(note: 'sarı kutuda'));
      final old = await add(box.id, NodeKind.item, 'Eski matkap');
      await store.moveToTrash(old.id);

      expect(store.search('matkap').map((n) => n.id), [drill.id]);
      expect(store.search('sarı').map((n) => n.id), [drill.id]);
      expect(store.search('garaj').map((n) => n.id), [box.id]);
      expect(store.search('   '), isEmpty);
    });
  });

  group('sıralama', () {
    test('gösterim sırası ayara göre değişir; elle dizilen sıra olduğu gibi durur', () async {
      Future<Node> add(String name, {NodeKind kind = NodeKind.item, DateTime? expires}) async {
        final n = store.draft(parentId: Roots.home, kind: kind).copyWith(name: name, expiresAt: expires);
        await store.commit(n);
        await Future<void>.delayed(const Duration(milliseconds: 3));
        return n;
      }

      await add('Zımba');
      await add('Adsız 10');
      await add('Raf', kind: NodeKind.container);
      await add('Adsız 2', expires: DateTime(2027, 5, 1));
      await add('çay', expires: DateTime(2026, 12, 1));
      await add('Dolap', kind: NodeKind.container);
      List<String> shown() => [for (final n in store.displayChildrenOf(Roots.home)) n.name];
      const manual = ['Raf', 'Dolap', 'Zımba', 'Adsız 10', 'Adsız 2', 'çay'];
      expect(shown(), manual, reason: 'varsayılan: elle sıra, klasörler önce');

      await store.updateSettings(store.settings.copyWith(deckSort: DeckSort.name));
      expect(shown(), ['Dolap', 'Raf', 'Adsız 2', 'Adsız 10', 'çay', 'Zımba'], reason: 'sayılar sayı gibi, harf farkı yok');

      await store.updateSettings(store.settings.copyWith(deckSort: DeckSort.newest));
      expect(shown(), ['Dolap', 'Raf', 'çay', 'Adsız 2', 'Adsız 10', 'Zımba']);

      await store.updateSettings(store.settings.copyWith(deckSort: DeckSort.expiry));
      expect(shown(), ['Dolap', 'Raf', 'çay', 'Adsız 2', 'Adsız 10', 'Zımba'], reason: 'tarihli olanlar önce, en yakın üstte');

      // Elle sıra hiç değişmedi; taşıma ve sayım onu kullanır.
      expect([for (final n in store.childrenOf(Roots.home)) n.name], manual);
      await store.updateSettings(store.settings.copyWith(deckSort: DeckSort.manual));
      expect(shown(), manual);

      // Gruplama kapalıyken hepsi tek sırada.
      await store.updateSettings(store.settings.copyWith(deckSort: DeckSort.name, groupKinds: false));
      expect(shown(), ['Adsız 2', 'Adsız 10', 'çay', 'Dolap', 'Raf', 'Zımba']);

      // Ayar veritabanında durur.
      expect((await AppSettings.load()).deckSort, DeckSort.name);
    });

    test('doğal karşılaştırma', () {
      final names = ['Kutu 10', 'kutu 2', 'Kutu', 'Çekiç', 'cekic 1', 'Kutu 02'];
      expect([...names]..sort(compareNatural), ['Çekiç', 'cekic 1', 'Kutu', 'kutu 2', 'Kutu 02', 'Kutu 10']);
    });
  });

  group('önbellekler', () {
    test('çöpteki klasörün altındakiler görünmez; geri gelince görünür; üstü olmayan kayıt görünür', () async {
      final dolap = await add(Roots.home, NodeKind.container, 'Dolap');
      final raf = await add(dolap.id, NodeKind.container, 'Raf');
      final pil = await add(raf.id, NodeKind.item, 'Pil');
      final bant = await add(Roots.home, NodeKind.item, 'Bant');
      bool live(Node n) => store.isLive(store.byId(n.id)!);
      expect([live(dolap), live(raf), live(pil), live(bant)], everyElement(isTrue));

      await store.moveToTrash(dolap.id);
      expect(live(dolap), isFalse);
      expect(live(raf), isFalse, reason: 'kendisi işaretli değil ama çöpteki klasörün içinde');
      expect(live(pil), isFalse, reason: 'iki seviye aşağıda');
      expect(live(bant), isTrue);
      expect(store.search('pil'), isEmpty);

      await store.restore(dolap.id);
      expect([live(dolap), live(raf), live(pil)], everyElement(isTrue));
      expect(store.search('pil').single.name, 'Pil');

      // Mağazada olmayan (ör. onay bekleyen) bir kayıt: üstüne göre karar verilir.
      final stray = store.draft(parentId: raf.id, kind: NodeKind.item).copyWith(name: 'Yeni');
      expect(store.isLive(stray), isTrue);
      await store.moveToTrash(raf.id);
      expect(store.isLive(stray), isFalse);
      expect(store.isLive(stray.copyWith(parentId: 'olmayan-klasor')), isTrue);
    });

    test('son kullanma durumu kayıt, gün ya da genel uyarı süresi değişince yeniden hesaplanır', () async {
      final today = DateTime(2026, 10, 1);
      final sut = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Süt',
            quantity: 2,
            purchasedAt: DateTime(2026, 1, 1),
            expiresAt: DateTime(2026, 12, 1),
          );
      await store.commit(sut);
      Node now() => store.byId(sut.id)!;
      await store.updateSettings(store.settings.copyWith(expiryWarning: const TimeSpan(1, SpanUnit.month)));
      expect(store.expiryOf(now(), today), ExpiryState.fine);
      expect(store.expiryOf(now(), today), ExpiryState.fine, reason: 'önbellekten de aynı');
      // Gün ilerleyince.
      expect(store.expiryOf(now(), DateTime(2026, 11, 20)), ExpiryState.soon);
      expect(store.expiryOf(now(), DateTime(2026, 12, 2)), ExpiryState.expired);
      // Genel uyarı süresi uzayınca aynı gün artık "yaklaşıyor".
      await store.updateSettings(store.settings.copyWith(expiryWarning: const TimeSpan(3, SpanUnit.month)));
      expect(store.expiryOf(now(), today), ExpiryState.soon);
      // Kayıt değişince (adet 0: tarihi sayılmaz).
      await store.commit(now().copyWith(quantity: 0));
      expect(store.expiryOf(now(), today), isNull);
    });

    test('sürükleme haberi listeleri bozmaz; ardından gelen değişiklik yine görünür', () async {
      final pil = await add(Roots.home, NodeKind.item, 'Pil');
      expect(store.shoppingItems, isEmpty);
      final before = store.stateStamp;
      store.setDragging(pil.id);
      expect(store.childrenOf(Roots.home).single.name, 'Pil');
      await store.setWanted(pil.id, true);
      store.setDragging(null);
      expect(store.shoppingItems.single.name, 'Pil', reason: 'türeyen liste değişikliği gördü');
      expect(store.stateStamp, isNot(before), reason: 'damga da');
      await store.setWanted(pil.id, false);
      expect(store.shoppingItems, isEmpty);
      await store.commit(store.byId(pil.id)!.copyWith(name: 'Kalem pil'));
      expect(store.search('pil').single.name, 'Kalem pil');
      expect(store.search('kalem'), hasLength(1));
    });

    test('klasörün kapağı: içindeki fotoğraflı kayıtlar, önce kendi seviyesi sonra alt klasörler; değişince yenilenir', () async {
      final oda = await add(Roots.home, NodeKind.container, 'Oda');
      final dolap = await add(oda.id, NodeKind.container, 'Dolap');
      await add(oda.id, NodeKind.item, 'Vida');
      Future<Node> photo(String parent, String name) async {
        final n = await add(parent, NodeKind.item, name);
        await store.commit(n.copyWith(imagePath: 'images/$name.jpg'));
        return store.byId(n.id)!;
      }

      List<String> cover(Node n) => [for (final c in store.coverOf(n.id)) c.name];
      expect(cover(oda), isEmpty, reason: 'fotoğrafsız kayıt kapağa girmez');

      await photo(dolap.id, 'Matkap');
      expect(cover(oda), ['Matkap'], reason: 'yalnızca klasör tutan klasör alt klasörün içini gösterir');
      expect(cover(dolap), ['Matkap']);

      final lamba = await photo(oda.id, 'Lamba');
      expect(cover(oda), ['Lamba', 'Matkap'], reason: 'kendi seviyesindeki önce');

      await photo(dolap.id, 'Testere');
      await photo(dolap.id, 'Pense');
      expect(cover(oda), hasLength(InventoryStore.coverSize));
      expect(cover(oda).first, 'Lamba');
      expect(cover(dolap), unorderedEquals(['Matkap', 'Testere', 'Pense']));

      await store.moveToTrash(lamba.id);
      expect(cover(oda), unorderedEquals(['Matkap', 'Testere', 'Pense']), reason: 'çöpe giden kapaktan düşer');

      // Fotoğraflı alt klasörün kendisi de kapağa girer.
      await store.commit(store.byId(dolap.id)!.copyWith(imagePath: 'images/dolap.jpg'));
      expect(cover(oda).first, 'Dolap');
      expect(identical(store.coverOf(oda.id), store.coverOf(oda.id)), isTrue, reason: 'önbellekten');
    });
  });

  group('beklemeden tamamen silme', () {
    /// Diskte gerçekten duran bir dosya (fotoğraf ya da ek).
    String onDiskFile(String rel) {
      File(AppPaths.abs(rel))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      AppPaths.forget(rel);
      return rel;
    }

    bool exists(String rel) => File(AppPaths.abs(rel)).existsSync();

    Future<Node> withFiles(String parent, NodeKind kind, String name, {String? image, String? file}) async {
      final draft = store.draft(parentId: parent, kind: kind).copyWith(
            name: name,
            imagePath: image,
            attachments: [
              if (file != null)
                Attachment(id: file, name: 'Kılavuz', addedAt: DateTime(2026), file: file, mime: 'application/pdf', size: 3),
            ],
          );
      await store.commit(draft);
      return store.byId(draft.id)!;
    }

    test('çöpten "hemen" silinen "Son silinenler"e girmez; fotoğrafı ve eki silinir, silme izi kalır', () async {
      final box = await withFiles(Roots.home, NodeKind.container, 'Sandık', image: onDiskFile('images/sandik.jpg'));
      final item = await withFiles(box.id, NodeKind.item, 'Battaniye', file: onDiskFile('files/kilavuz.pdf'));
      await store.moveToTrash(box.id);

      await store.deleteForever(box.id, now: true);

      expect(store.byId(box.id), isNull);
      expect(store.byId(item.id), isNull);
      expect(store.recentlyPurged, isEmpty);
      expect(exists('images/sandik.jpg'), isFalse);
      expect(exists('files/kilavuz.pdf'), isFalse);
      final tombs = store.snapshot().tombstones;
      expect(tombs.keys, containsAll([box.id, item.id]), reason: 'başka cihazdaki kopya geri getirmesin');
    });

    test('başka bir kaydın da kullandığı fotoğraf silinmez', () async {
      final photo = onDiskFile('images/ortak.jpg');
      final a = await withFiles(Roots.home, NodeKind.item, 'Matkap', image: photo);
      await withFiles(Roots.home, NodeKind.item, 'Matkap kopyası', image: photo);
      await store.moveToTrash(a.id);
      await store.deleteForever(a.id, now: true);
      expect(exists('images/ortak.jpg'), isTrue);
    });

    test('çöp "hemen" boşalınca arşivdeki eskiler yerinde kalır', () async {
      final old = await withFiles(Roots.home, NodeKind.item, 'Eski', image: onDiskFile('images/eski.jpg'));
      await store.moveToTrash(old.id);
      await store.emptyTrash();
      expect(store.recentlyPurged.map((r) => r.node.name), ['Eski']);

      final yeni = await withFiles(Roots.home, NodeKind.item, 'Yeni', image: onDiskFile('images/yeni.jpg'));
      await store.moveToTrash(yeni.id);
      await store.emptyTrash(now: true);
      expect(store.trash, isEmpty);
      expect(store.recentlyPurged.map((r) => r.node.name), ['Eski']);
      expect(exists('images/yeni.jpg'), isFalse);
      expect(exists('images/eski.jpg'), isTrue, reason: 'hâlâ geri getirilebilir');
    });

    test('"Son silinenler"den tek kayıt (içindekileriyle) ya da hepsi tamamen silinir', () async {
      final box = await withFiles(Roots.home, NodeKind.container, 'Kutu', image: onDiskFile('images/kutu.jpg'));
      await withFiles(box.id, NodeKind.item, 'Pil', file: onDiskFile('files/pil.pdf'));
      final lamba = await withFiles(Roots.home, NodeKind.item, 'Lamba', image: onDiskFile('images/lamba.jpg'));
      await store.deleteForever(box.id);
      await store.deleteForever(lamba.id);
      expect(store.recentlyPurged.map((r) => r.node.name).toSet(), {'Kutu', 'Lamba'});

      await store.discardPurged(box.id);
      expect(store.recentlyPurged.map((r) => r.node.name), ['Lamba']);
      expect(exists('images/kutu.jpg'), isFalse);
      expect(exists('files/pil.pdf'), isFalse, reason: 'klasörle birlikte silinen içindeki de gider');
      expect(exists('images/lamba.jpg'), isTrue);

      await store.discardPurged();
      expect(store.recentlyPurged, isEmpty);
      expect(exists('images/lamba.jpg'), isFalse);

      // Yeniden açılışta da arşiv boş (diske yazıldı).
      final reopened = InventoryStore();
      await reopened.init();
      expect(reopened.recentlyPurged, isEmpty);
    });
  });

  group('tarayıcının seri sayımı', () {
    test('eşya kartın + düğmesi gibi bir artar: paketli eşyada en yeni pakete, adedi tutulmayan 1\'den', () async {
      final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
      final early = DateTime(2026, 11, 5);
      final later = DateTime(2026, 11, 12);
      final draft = await add(kutu.id, NodeKind.item, 'Süt');
      await store.commit(withLots(draft, [Lot(2, early), Lot(4, later)]));
      expect(store.byId(draft.id)!.quantity, 6);
      expect(await store.countOne(draft.id), 7);
      expect(store.byId(draft.id)!.lots, [Lot(2, early), Lot(5, later)], reason: 'paketler toplamla tutar');

      final pil = await add(kutu.id, NodeKind.item, 'Pil');
      expect(pil.quantity, isNull);
      expect(await store.countOne(pil.id), 1, reason: 'eskiden 2 yazıyordu');
    });

    test('klasör, çöpteki ve olmayan kayıt sayılmaz', () async {
      final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
      final pil = await add(kutu.id, NodeKind.item, 'Pil');
      expect(await store.countOne(kutu.id), isNull);
      expect(store.byId(kutu.id)!.quantity, isNull, reason: 'klasörün adedi olmaz');
      await store.moveToTrash(kutu.id);
      expect(await store.countOne(pil.id), isNull, reason: 'çöpteki klasörün içinde');
      expect(store.byId(pil.id)!.quantity, isNull);
      expect(await store.countOne('olmayan'), isNull);
    });
  });

  group('çöpteki klasörün içindekiler', () {
    test('sık kullanılanlarda görünmez, sayılmaz, son açık yer olarak yazılmaz', () async {
      final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
      final raf = await add(kutu.id, NodeKind.container, 'Raf');
      final pil = await add(raf.id, NodeKind.item, 'Pil');
      await store.toggleFavorite(pil.id);
      expect(store.favorites.map((n) => n.id), [pil.id]);
      await store.moveToTrash(kutu.id);
      // Yalnızca Kutu işaretli; içindekilerin kendi silinme anı yok.
      expect(store.byId(pil.id)!.isDeleted, isFalse);
      expect(store.favorites, isEmpty);
      expect(store.totalRecordCount, store.visibleRecordCount,
          reason: 'Envanterler sayfası ile sol menü aynı sayıyı göstersin');
      await store.rememberLevel(raf.id);
      expect(store.settings.lastLevel, isNull);
      // Ortak kullanım sayfası sorumluların klasörlerini buradan listeler.
      expect(store.allContainers.map((n) => n.id), isNot(contains(raf.id)));
    });
  });

  group('toplu ekleme (seri ekleme)', () {
    test('yeni kayıtlar tek yazımda: adsızlar sırayla numaralanır, damgalanır, ekran bir kez yenilenir', () async {
      final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
      await store.commit(store.draft(parentId: kutu.id, kind: NodeKind.item));
      expect(store.childrenOf(kutu.id).map(store.nameOf), ['Adsız 1']);
      var notified = 0;
      void count() => notified++;
      store.addListener(count);
      addTearDown(() => store.removeListener(count));
      final first = store.draft(parentId: kutu.id, kind: NodeKind.item);
      final drafts = [
        for (final (i, name) in ['', 'Pense', ''].indexed)
          (i == 0 ? first : store.draft(parentId: kutu.id, kind: NodeKind.item))
              .copyWith(name: name, sortIndex: first.sortIndex + i),
      ];
      await store.addAll(drafts);
      expect(notified, 1, reason: '200 fotoğrafta 200 yeniden çizim olmasın');
      expect(store.childrenOf(kutu.id).map(store.nameOf), ['Adsız 1', 'Adsız 2', 'Pense', 'Adsız 3']);
      final pense = store.byId(drafts[1].id)!;
      expect(pense.updatedBy, store.authorId);
      expect(pense.fieldTimes, isNotEmpty, reason: 'gruplar damgalı: eşitlemede eski sürüme yenilmesin');
      expect(store.settings.recent, containsAll([for (final d in drafts) d.id]));
      final reopened = InventoryStore();
      await reopened.init();
      expect(reopened.childrenOf(kutu.id).map(reopened.nameOf), ['Adsız 1', 'Adsız 2', 'Pense', 'Adsız 3']);
    });
  });
}
