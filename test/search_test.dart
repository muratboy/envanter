import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/core/text_match.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Arama harf farkı gözetmez; boş aramada son dokunulanlar görünür.
void main() {
  group('harf katlama', () {
    test('Türkçe ve şapkalı harfler düz harfe iner, uzunluk değişmez', () {
      for (final (raw, folded) in [
        ('ISITICI', 'isitici'),
        ('ısıtıcı', 'isitici'),
        ('İstanbul', 'istanbul'),
        ('Çekiç', 'cekic'),
        ('Soğan', 'sogan'),
        ('Şarj ALETİ', 'sarj aleti'),
        ('Ütü', 'utu'),
        ('Kâğıt', 'kagit'),
        ('Café Crème', 'cafe creme'),
      ]) {
        expect(foldForSearch(raw), folded, reason: raw);
        expect(foldForSearch(raw).length, raw.length, reason: 'vurgulama aynı yerleri kullanır');
      }
    });

    test('kelimeler ayrı ayrı aranır, yerleri özgün metinde birleşik döner', () {
      final tokens = searchTokens('  kırmızı   KALEM ');
      expect(tokens, ['kirmizi', 'kalem']);
      expect(matchRanges('Kalem (Kırmızı)', tokens), [(0, 5), (7, 14)]);
      // Üst üste binen eşleşmeler tek parça olur.
      expect(matchRanges('Şarjlı', searchTokens('sarj arjl')), [(0, 5)]);
      expect(matchRanges('Tornavida', searchTokens('pense')), isEmpty);
    });

    test('uzun notun eşleşen yerinin çevresi kesilir', () {
      const note = 'Garajın arka tarafındaki metal dolabın en üst rafında, '
          'mavi kapaklı plastik kutunun içinde duruyor; yanında yedek uçlar var.';
      final snippet = snippetAround(note, searchTokens('yedek'));
      expect(snippet, startsWith('…'));
      expect(snippet, contains('yedek uçlar'));
      expect(snippetAround('kısa not', searchTokens('not')), 'kısa not');
    });
  });

  group('mağazada', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppPaths.useDirectory(Directory.systemTemp.createTempSync('envanter_search').path);
    });

    late InventoryStore store;

    setUp(() async {
      await AppDatabase.instance.openForTest(inMemory: true);
      store = InventoryStore();
      await store.init();
      await store.updateSettings(store.settings.copyWith(language: AppLanguage.turkish));
    });

    tearDown(() async => AppDatabase.instance.close());

    Future<Node> add(String parent, NodeKind kind, String name, {String? note}) async {
      final draft = store.draft(parentId: parent, kind: kind).copyWith(name: name, note: note);
      await store.commit(draft);
      return store.byId(draft.id)!;
    }

    test('Türkçe harfsiz ve büyük harfli yazılan bulunur', () async {
      final garaj = await add(Roots.home, NodeKind.container, 'Garaj');
      final isitici = await add(garaj.id, NodeKind.item, 'ISITICI');
      final cekic = await add(garaj.id, NodeKind.item, 'Çekiç');

      expect(store.search('ısıtıcı').map((n) => n.id), [isitici.id]);
      expect(store.search('isitici').map((n) => n.id), [isitici.id]);
      expect(store.search('cekic').map((n) => n.id), [cekic.id]);
      expect(store.search('ÇEKİÇ').map((n) => n.id), [cekic.id]);
    });

    test('barkod: okutulan kod görünür kaydı bulur; rakamları yazınca da çıkar; çöpteki bulunmaz', () async {
      final garaj = await add(Roots.home, NodeKind.container, 'Garaj');
      final pil = await add(garaj.id, NodeKind.item, 'Pil');
      await store.commit(pil.copyWith(barcode: '8690504012345'));
      expect(store.byBarcode('8690504012345').single.id, pil.id);
      expect(store.byBarcode(' 8690504012345 ').single.id, pil.id);
      expect(store.byBarcode('0000000000000'), isEmpty);
      expect(store.search('8690504').map((n) => n.id), [pil.id]);

      // Aynı üründen iki yerde.
      final yedek = await add(Roots.home, NodeKind.item, 'Yedek pil');
      await store.commit(yedek.copyWith(barcode: '8690504012345'));
      expect(store.byBarcode('8690504012345').map((n) => n.name), unorderedEquals(['Pil', 'Yedek pil']));

      // Çöpteki klasörün içindeki bulunmaz; barkodu kaldırılan da.
      await store.moveToTrash(garaj.id);
      expect(store.byBarcode('8690504012345').single.name, 'Yedek pil');
      await store.commit(store.byId(yedek.id)!.copyWith(clearBarcode: true));
      expect(store.byBarcode('8690504012345'), isEmpty);
      await store.restore(garaj.id);
      expect(store.byBarcode('8690504012345').single.id, pil.id);
    });

    test('birden çok kelime: her biri adda ya da notta geçmeli', () async {
      final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
      final kirmizi = await add(kutu.id, NodeKind.item, 'Kalem', note: 'kırmızı, kalın uçlu');
      await add(kutu.id, NodeKind.item, 'Kalem', note: 'mavi');
      await add(kutu.id, NodeKind.item, 'Kırmızı boya');

      expect(store.search('kırmızı kalem').map((n) => n.id), [kirmizi.id]);
    });

    test('adı tam tutan önce, adı böyle başlayan sonra, yalnızca notunda geçen en son', () async {
      final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
      final notta = await add(kutu.id, NodeKind.item, 'Tornavida', note: 'pil takımıyla');
      final basta = await add(kutu.id, NodeKind.item, 'Pil şarj aleti');
      final tam = await add(kutu.id, NodeKind.item, 'Pil');

      expect(store.search('pil').map((n) => n.id), [tam.id, basta.id, notta.id]);
    });

    test('çöpe atılan klasörün içindekiler aramada çıkmaz, geri alınınca döner', () async {
      final kutu = await add(Roots.home, NodeKind.container, 'Eski kutu');
      final matkap = await add(kutu.id, NodeKind.item, 'Matkap');
      await store.moveToTrash(kutu.id);
      expect(store.search('matkap'), isEmpty, reason: 'atası çöpte');

      await store.restore(kutu.id);
      expect(store.search('matkap').map((n) => n.id), [matkap.id]);
    });

    test('son dokunulanlar: eklenen, düzenlenen ve taşınan en üstte; sıralama girmez', () async {
      final mutfak = await add(Roots.home, NodeKind.container, 'Mutfak');
      final balkon = await add(Roots.home, NodeKind.container, 'Balkon');
      final tuz = await add(mutfak.id, NodeKind.item, 'Tuz');
      final biber = await add(mutfak.id, NodeKind.item, 'Biber');
      expect(store.recent.map((n) => n.name), ['Biber', 'Tuz', 'Balkon', 'Mutfak']);

      await store.move(tuz.id, balkon.id);
      expect(store.recent.first.id, tuz.id, reason: 'taşınan en üste çıkar');

      // Yalnızca sırası değişen kayıtlar "dokunulmuş" sayılmaz.
      await store.reorder(Roots.home, 0, 1);
      expect(store.recent.first.id, tuz.id);

      // Çöpe atılan listede görünmez.
      await store.moveToTrash(biber.id);
      expect(store.recent.map((n) => n.id), isNot(contains(biber.id)));
    });

    test('karşıdan gelen kayıtlar son dokunulanlara girmez', () async {
      final kendi = await add(Roots.home, NodeKind.container, 'Kendi');
      final now = DateTime.now();
      final gelen = Node(
        id: 'uzak-1',
        parentId: null,
        kind: NodeKind.item,
        name: 'Uzaktan',
        color: 0xFFE0C9A6,
        sortIndex: 5,
        createdAt: now,
        updatedAt: now,
      );
      await store.mergeRemote(nodes: {gelen.id: gelen}, tombstones: const {});
      expect(store.byId(gelen.id), isNotNull);
      expect(store.recent.map((n) => n.id), [kendi.id]);
    });

    group('yedek hatırlatması', () {
      Future<void> addMany(int n) async {
        for (var i = 0; i < n; i++) {
          await add(Roots.home, NodeKind.container, 'Kutu $i');
        }
      }

      test('birkaç kayıtlık yeni envanter rahatsız edilmez', () async {
        await addMany(3);
        final later = DateTime.now().add(const Duration(days: 60));
        expect(store.backupDueAt(later), isFalse, reason: 'beşten az kayıt');
      });

      test('hiç yedek yoksa ilk kayıttan bir hafta sonra hatırlatılır', () async {
        await addMany(6);
        final now = DateTime.now();
        expect(store.backupDueAt(now.add(const Duration(days: 2))), isFalse);
        expect(store.backupDueAt(now.add(const Duration(days: 8))), isTrue);
      });

      test('yedekten bir ay sonra, yalnızca arada bir şey değiştiyse', () async {
        await addMany(6);
        await store.markBackedUp();
        expect(store.changesSinceBackup, 0);
        final month = DateTime.now().add(const Duration(days: 31));
        expect(store.backupDueAt(month), isFalse, reason: 'değişen yok');

        await Future<void>.delayed(const Duration(milliseconds: 5));
        await add(Roots.home, NodeKind.container, 'Yeni');
        expect(store.changesSinceBackup, 1);
        expect(store.backupDueAt(DateTime.now().add(const Duration(days: 10))), isFalse);
        expect(store.backupDueAt(month), isTrue);
      });

      test('"sonra" bir hafta susturur', () async {
        await addMany(6);
        final due = DateTime.now().add(const Duration(days: 10));
        await store.snoozeBackupReminder(due);
        expect(store.backupDueAt(due.add(const Duration(days: 3))), isFalse);
        expect(store.backupDueAt(due.add(const Duration(days: 8))), isTrue);
      });

      test('yedek zamanı cihazda kalır, uygulama yeniden açılınca da durur', () async {
        final at = DateTime(2026, 9, 1, 12);
        await store.markBackedUp(at);
        final reopened = InventoryStore();
        await reopened.init();
        expect(reopened.settings.lastBackupAt, at);
      });
    });

    group('toplu işlem', () {
      test('seçilenler birlikte taşınır; seçili klasörün içindeki seçili kayıt klasörle kalır', () async {
        final garaj = await add(Roots.home, NodeKind.container, 'Garaj');
        final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
        final pil = await add(kutu.id, NodeKind.item, 'Pil');
        final tel = await add(Roots.home, NodeKind.item, 'Tel');

        final moved = await store.moveMany([kutu.id, pil.id, tel.id, garaj.id], garaj.id);
        // Garaj kendi içine gidemez, pil kutuyla birlikte gider.
        expect(moved.map((n) => n.id).toSet(), {kutu.id, tel.id});
        expect(store.byId(kutu.id)!.parentId, garaj.id);
        expect(store.byId(tel.id)!.parentId, garaj.id);
        expect(store.byId(pil.id)!.parentId, kutu.id, reason: 'kutudan çıkarılmadı');
        expect(store.childrenOf(garaj.id).map((n) => n.name), ['Kutu', 'Tel']);
      });

      test('çekmeceye alınan kayıp eşya bulunmuş olur', () async {
        final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
        final pil = await add(kutu.id, NodeKind.item, 'Pil');
        await store.markLost(pil.id);

        final moved = await store.moveMany([pil.id], Roots.drawer);
        expect(store.byId(pil.id)!.isLost, isFalse);
        expect(store.childrenOf(Roots.drawer).map((n) => n.id), [pil.id]);

        // Geri alınınca yeniden kayıp, son yeri de durur.
        await store.restorePlacements(moved);
        expect(store.byId(pil.id)!.isLost, isTrue);
        expect(store.byId(pil.id)!.lostFrom, kutu.id);
        expect(store.childrenOf(Roots.lost).map((n) => n.id), [pil.id]);
      });

      test('taşınanlar destedeki sırasını korur; geri alınca eski sırasına döner', () async {
        final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
        final a = await add(Roots.home, NodeKind.item, 'A');
        final b = await add(Roots.home, NodeKind.item, 'B');
        final c = await add(Roots.home, NodeKind.item, 'C');

        // Dokunma sırası C, A: hedefte yine A, C.
        final moved = await store.moveMany([c.id, a.id], kutu.id);
        expect(store.childrenOf(kutu.id).map((n) => n.name), ['A', 'C']);
        expect(store.childrenOf(Roots.home).map((n) => n.name), ['Kutu', 'B']);

        await store.restorePlacements(moved);
        expect(store.childrenOf(Roots.home).map((n) => n.id), [kutu.id, a.id, b.id, c.id]);
        expect(store.childrenOf(kutu.id), isEmpty);
      });

      test('çöpe atılanlar geri alınınca yerlerine döner', () async {
        final kutu = await add(Roots.home, NodeKind.container, 'Kutu');
        final pil = await add(kutu.id, NodeKind.item, 'Pil');
        final tel = await add(Roots.home, NodeKind.item, 'Tel');

        final trashed = await store.trashMany([kutu.id, pil.id, tel.id]);
        expect(trashed.toSet(), {kutu.id, tel.id}, reason: 'pil kutuyla birlikte gizlenir');
        expect(store.childrenOf(Roots.home), isEmpty);

        await store.restoreMany(trashed);
        expect(store.childrenOf(Roots.home).map((n) => n.name).toSet(), {'Kutu', 'Tel'});
        expect(store.childrenOf(kutu.id).map((n) => n.id), [pil.id]);
      });
    });
  });
}
