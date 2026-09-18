import 'dart:convert';
import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/services/attachment_service.dart';
import 'package:envanter/services/backup_service.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/fields.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ekler: model, doğrulama, birleşme, dosyaların ömrü, yedek.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory work;
  setUp(() => work = Directory.systemTemp.createTempSync('envanter_ekler'));
  tearDown(() async {
    await AppDatabase.instance.close();
    if (work.existsSync()) work.deleteSync(recursive: true);
  });

  Future<InventoryStore> device(String name) async {
    final dir = Directory('${work.path}/$name')..createSync(recursive: true);
    AppPaths.useDirectory(dir.path);
    await AppDatabase.instance.openForTest();
    final store = InventoryStore()..authorId = name;
    await store.init();
    return store;
  }

  /// Diskte gerçekten duran bir dosya eki.
  Attachment fileOf(String rel, List<int> bytes, {String name = 'Kılavuz', String mime = 'application/pdf'}) {
    File(AppPaths.abs(rel))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    AppPaths.forget(rel);
    return Attachment(
      id: rel,
      name: name,
      addedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      file: rel,
      mime: mime,
      size: bytes.length,
    );
  }

  bool onDisk(String rel) => File(AppPaths.abs(rel)).existsSync();

  group('model', () {
    final at = DateTime.fromMillisecondsSinceEpoch(1727000000000);

    test('dosya ve bağlantı yazılıp okunur; türü MIME\'dan anlaşılır', () {
      final list = [
        Attachment(id: 'a', name: 'Kılavuz', addedAt: at, file: 'files/k.pdf', mime: 'application/pdf', size: 3400000),
        Attachment(id: 'b', name: 'Garanti', addedAt: at, file: 'files/g.jpg', mime: 'image/jpeg', size: 200),
        Attachment(id: 'c', name: 'Sorun', addedAt: at, file: 'files/s.mp4', mime: 'video/mp4', size: 9),
        Attachment(id: 'd', name: 'Nasıl kullanılır', addedAt: at, url: 'https://www.youtube.com/watch?v=abc'),
      ];
      final back = Attachment.decode(Attachment.encode(list));
      expect(back, list);
      expect(back.map((a) => a.kind), [
        AttachmentKind.document,
        AttachmentKind.photo,
        AttachmentKind.video,
        AttachmentKind.link,
      ]);
      expect(back[0].extension, 'PDF');
      expect(back[3].host, 'youtube.com');
      expect(Attachment.encode(const []), isNull);
      expect(Attachment.decode(null), isEmpty);
      expect(Attachment.decode('bozuk'), isEmpty);
    });

    test('güvensiz yol ve adres taşıyan ek düşer', () {
      Map<String, Object?> raw(String id, {String? f, String? u}) => {'i': id, 'n': id, 'a': 1, 'f': ?f, 'u': ?u};
      final decoded = Attachment.decode(jsonEncode([
        raw('iyi', f: 'files/a.pdf'),
        raw('disari', f: 'files/../envanter.db'),
        raw('baska-klasor', f: 'databases/envanter.db'),
        raw('yerel', u: 'file:///data/data/x'),
        raw('icerik', u: 'content://sms'),
        raw('betik', u: 'javascript:alert(1)'),
        raw('ikisi', f: 'files/b.pdf', u: 'https://ornek.com'),
        raw('hicbiri'),
        raw('iyi', f: 'files/c.pdf'), // aynı kimlik ikinci kez
        raw('baglanti', u: 'http://ornek.com/kilavuz'),
      ]));
      // Aynı anda eklenenler kimlik sırasında (her cihazda aynı sıra).
      expect(decoded.map((a) => a.id), ['baglanti', 'iyi']);
      expect(decoded.last.file, 'files/a.pdf', reason: 'aynı kimliğin ilki geçerli');
    });

    test('saklanan ek sayısı sınırlı; kesilen kısım sıraya değil içeriğe bağlı', () {
      Map<String, Object?> raw(int i) => {'i': 'e$i', 'n': 'e', 'a': 1000 + i, 'u': 'https://ornek.com/$i'};
      final count = Attachment.maxStored + 40;
      final forward = Attachment.decode(jsonEncode([for (var i = 0; i < count; i++) raw(i)]));
      final backward = Attachment.decode(jsonEncode([for (var i = count - 1; i >= 0; i--) raw(i)]));
      expect(forward, hasLength(Attachment.maxStored));
      expect(Attachment.maxStored, greaterThan(Attachment.maxCount), reason: 'iki cihazın ekleri birleşince 40 aşılabilir');
      expect(backward.map((a) => a.id), forward.map((a) => a.id), reason: 'hangi sırada gelirse gelsin aynı ekler kalır');
      expect(forward.first.id, 'e0');
    });

    test('çıkarılan ekin izi eklerle aynı metinde taşınır; okununca ayrılır', () {
      final live = Attachment(id: 'a', name: 'Kılavuz', addedAt: at, url: 'https://ornek.com/k');
      final renamed = live.renamed('Kullanım kılavuzu').touched(at.add(const Duration(seconds: 5)));
      final text = Attachment.encode([renamed], {'b': 77, 'c': 99})!;
      expect(Attachment.decode(text), [renamed]);
      expect(Attachment.decode(text).single.stamp, at.millisecondsSinceEpoch + 5000);
      expect(Attachment.decodeTombs(text), {'b': 77, 'c': 99});
      expect(Attachment.encode(const [], const {}), isNull);
      expect(Attachment.encode(const [], {'b': 77}), isNotNull, reason: 'yalnızca iz kalsa da yazılır');
      // Aynı içerik, hangi sırayla verilirse verilsin aynı metin.
      final other = Attachment(id: 'z', name: 'Video', addedAt: at, url: 'https://ornek.com/v');
      expect(Attachment.encode([other, live], {'c': 1, 'b': 2}), Attachment.encode([live, other], {'b': 2, 'c': 1}));
      // Bozuk iz atılır; hâlâ duran ekin izi sayılmaz.
      final odd = jsonEncode([
        live.toJson(),
        {'i': 'a', 'x': 5},
        {'i': 'q', 'x': 'dün'},
        {'i': '', 'x': 5},
        {'i': 'k', 'x': 9},
      ]);
      expect(Attachment.decodeTombs(odd), {'k': 9});
      expect(Attachment.decode(odd), [live]);
    });

    test('ağdan gelen kayıtta ekler süzülür', () {
      final node = sanitizeNode({
        'id': 'n1',
        'kind': 'item',
        'name': 'Matkap',
        'color': 0xFF112233,
        'created_at': 1,
        'updated_at': 1,
        'attachments': jsonEncode([
          {'i': 'a', 'n': 'Kılavuz', 'a': 1, 'f': 'files/k.pdf', 'm': 'application/pdf', 's': 12},
          {'i': 'b', 'n': 'Tuzak', 'a': 1, 'f': '../../databases/envanter.db'},
        ]),
      })!;
      expect(node.attachments.single.name, 'Kılavuz');
      expect(node.attachments.single.size, 12);
      // Metin olmayan alan kaydı düşürmez, ekleri düşürür.
      expect(sanitizeNode({'id': 'n2', 'kind': 'item', 'color': 1, 'created_at': 1, 'updated_at': 1, 'attachments': 7})!
          .attachments, isEmpty);
    });

    test('adres şemasız yazılırsa https eklenir; geçersiz adres bağlantı olmaz', () {
      final a = AttachmentService.link('youtube.com/watch?v=1', '')!;
      expect(a.url, 'https://youtube.com/watch?v=1');
      expect(a.name, 'youtube.com', reason: 'başlık verilmezse site adı');
      expect(AttachmentService.link(' https://ornek.com/a ', 'Kılavuz')!.name, 'Kılavuz');
      expect(AttachmentService.link('', 'x'), isNull);
      expect(AttachmentService.link('merhaba', 'x'), isNull);
      expect(AttachmentService.link('file:///sdcard/a.pdf', 'x'), isNull);
    });

    test('boyut dile göre yazılır', () {
      expect(const TrStrings().fileSize(900), '900 B');
      expect(const TrStrings().fileSize(840 * 1024), '840 KB');
      expect(const TrStrings().fileSize(3355443), '3,2 MB');
      expect(const EnStrings().fileSize(3355443), '3.2 MB');
      expect(const EnStrings().fileSize(480 * 1024 * 1024), '480 MB');
    });
  });

  group('eşitleme', () {
    Node base() => stampChanges(
          null,
          Node(
            id: 'n',
            parentId: null,
            kind: NodeKind.item,
            name: 'Matkap',
            color: 1,
            sortIndex: 0,
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
          DateTime.fromMillisecondsSinceEpoch(1000),
        );

    Attachment link(String id, int addedMs) => Attachment(
          id: id,
          name: id,
          addedAt: DateTime.fromMillisecondsSinceEpoch(addedMs),
          url: 'https://ornek.com/$id',
        );
    DateTime ms(int v) => DateTime.fromMillisecondsSinceEpoch(v);
    List<String> ids(Node n) => [for (final a in n.attachments) a.id];
    // İki yönde de birleştirir, sonucun aynı olduğunu doğrular.
    Node both(Node a, Node b) {
      final one = mergeNode(a, b);
      final two = mergeNode(b, a);
      expect(sameVersion(one, two), isTrue, reason: 'sıra ne olursa olsun aynı sonuç');
      expect(ids(one), ids(two));
      expect(stateStampOf([one], const {}), stateStampOf([two], const {}));
      expect(sameVersion(mergeNode(one, a), one), isTrue, reason: 'yeniden birleştirmek bir şey değiştirmez');
      expect(sameVersion(mergeNode(one, b), one), isTrue);
      return one;
    }

    test('iki cihazda ayrı ayrı eklenen ekler birlikte kalır', () {
      final start = base();
      final ayse = stampChanges(start, start.copyWith(attachments: [link('kilavuz', 1500)]), ms(2000));
      final ali = stampChanges(start, start.copyWith(attachments: [link('garanti', 1600)]), ms(3000));
      final merged = both(ayse, ali);
      expect(ids(merged), ['kilavuz', 'garanti'], reason: 'eklenme sırasıyla');
      expect(merged.timeOf(NodeField.attachments), 3000);

      // Birleşen kaydın zamanı ve yazarı Ali'ninkiyle aynı, ama içeriği değil:
      // damga da sürüm karşılaştırması da bunu görmeli, yoksa Ali öteki eki hiç almazdı.
      expect(merged.updatedAt, ali.updatedAt);
      expect(sameVersion(merged, ali), isFalse);
      expect(stateStampOf([merged], const {}), isNot(stateStampOf([ali], const {})));
      expect(ids(mergeNode(ali, merged)), ['kilavuz', 'garanti']);
    });

    test('çıkarılan ek çıkmış kalır: eki hâlâ tutan cihazla birleşince geri gelmez', () {
      final start = stampChanges(base(), base().copyWith(attachments: [link('kilavuz', 1500), link('garanti', 1600)]), ms(2000));
      final ayse = stampChanges(start, start.copyWith(attachments: [start.attachments.last]), ms(3000));
      expect(ayse.attachmentTombs, {'kilavuz': 3000});
      // Ali bu arada başka bir ek ekledi; listesi daha yeni ama çıkarmayı bilmiyor.
      final ali = stampChanges(start, start.copyWith(attachments: [...start.attachments, link('video', 3500)]), ms(4000));
      final merged = both(ayse, ali);
      expect(ids(merged), ['garanti', 'video']);
      expect(merged.attachmentTombs, {'kilavuz': 3000});
      // Eski haliyle kalmış üçüncü bir cihaz da geri getiremez.
      expect(ids(both(merged, start)), ['garanti', 'video']);
    });

    test('adı değişen ekte son ad kalır; çıkarıldıktan sonra adı değişen ek geri gelir', () {
      final start = stampChanges(base(), base().copyWith(attachments: [link('kilavuz', 1500)]), ms(2000));
      Node rename(String name, int at) =>
          stampChanges(start, start.copyWith(attachments: [start.attachments.single.renamed(name)]), ms(at));
      final ayse = rename('Kullanım kılavuzu', 3000);
      final ali = rename('PDF', 4000);
      expect(both(ayse, ali).attachments.single.name, 'PDF');
      expect(ayse.attachments.single.stamp, 3000, reason: 'adı değişen ek o ana damgalanır');
      expect(start.attachments.single.stamp, 2000);

      final removed = stampChanges(start, start.copyWith(attachments: const []), ms(3500));
      expect(both(removed, ayse).attachments, isEmpty, reason: 'ad değişimi çıkarmadan önce');
      final back = both(removed, ali);
      expect(back.attachments.single.name, 'PDF', reason: 'çıkarıldıktan sonra değişti: veri kaybolmasın');
      expect(back.attachmentTombs, isEmpty);
      // Aynı anda çıkarma ve ad değişimi: iz kazanır (keyfi ama her yerde aynı).
      expect(both(stampChanges(start, start.copyWith(attachments: const []), ms(4000)), ali).attachments, isEmpty);
    });

    test('ek değişikliği reddedilince bizdeki liste her yerde geçerli kalır', () {
      final start = stampChanges(base(), base().copyWith(attachments: [link('kilavuz', 1500), link('garanti', 1600)]), ms(2000));
      // Karşıdaki: kılavuzu çıkardı, garantinin adını değiştirdi, video ekledi.
      final theirs = stampChanges(
        start,
        start.copyWith(attachments: [start.attachments.last.renamed('Fatura'), link('video', 2500)]),
        ms(3000),
      );
      final kept = rejectAttachments(start, theirs, ms(5000));
      final merged = both(kept, theirs);
      expect(ids(merged), ['kilavuz', 'garanti']);
      expect(merged.attachments.last.name, 'garanti');
      expect(merged.attachmentTombs, {'video': 5000});
      expect(merged.attachments, start.attachments, reason: 'görünen liste bizdekiyle aynı');
    });

    test('ekler ayrı grup: biri ad değiştirir, öteki ek eklerse ikisi de kalır', () {
      final start = base();
      final link = Attachment(
        id: 'a',
        name: 'Video',
        addedAt: DateTime.fromMillisecondsSinceEpoch(2000),
        url: 'https://ornek.com/v',
      );
      final ayse = stampChanges(start, start.copyWith(name: 'Darbeli matkap'), DateTime.fromMillisecondsSinceEpoch(2000));
      final ali = stampChanges(start, start.copyWith(attachments: [link]), DateTime.fromMillisecondsSinceEpoch(3000));
      final one = mergeNode(ayse, ali);
      final two = mergeNode(ali, ayse);
      expect(one.name, 'Darbeli matkap');
      expect(one.attachments, [link]);
      expect(sameVersion(one, two), isTrue, reason: 'sıra ne olursa olsun aynı sonuç');
      expect(stateStampOf([start], const {}), isNot(stateStampOf([ali], const {})), reason: 'ek damgayı değiştirir');
    });
  });

  group('dosyalar', () {
    test('ek kayıttan çıkarılınca dosyası silinir; başka kayıt kullanıyorsa durur', () async {
      final store = await device('ayse');
      final kilavuz = fileOf('files/k.pdf', [1, 2, 3]);
      final ortak = fileOf('files/ortak.pdf', [4, 5]);
      final matkap = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Matkap',
            attachments: [kilavuz, ortak],
          );
      final testere = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Testere',
            attachments: [ortak],
          );
      await store.commit(matkap);
      await store.commit(testere);

      await store.commit(store.byId(matkap.id)!.copyWith(attachments: const []));
      store.discardFiles(['files/k.pdf', 'files/ortak.pdf']);
      expect(onDisk('files/k.pdf'), isFalse);
      expect(onDisk('files/ortak.pdf'), isTrue, reason: 'Testere hâlâ kullanıyor');
    });

    test('kalıcı silinen kaydın eki "Son silinenler"de dururken silinmez, geri gelince açılır', () async {
      final store = await device('ayse');
      final a = fileOf('files/garanti.jpg', [9, 9], mime: 'image/jpeg');
      final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Ütü', attachments: [a]);
      await store.commit(n);
      await store.deleteForever(n.id);
      store.discardFiles(['files/garanti.jpg']);
      expect(onDisk('files/garanti.jpg'), isTrue);
      await store.restorePurged(n.id);
      expect(store.byId(n.id)!.attachments.single.file, 'files/garanti.jpg');
    });

    test('eksik ek istenir; yalnızca bende tutulan kaydın eki ne istenir ne verilir', () async {
      final store = await device('ayse');
      final var_ = fileOf('files/var.pdf', [1]);
      final ozel = fileOf('files/ozel.pdf', [2]);
      final yok = Attachment(
        id: 'y',
        name: 'Gelmedi',
        addedAt: DateTime.fromMillisecondsSinceEpoch(1),
        file: 'files/yok.mp4',
        mime: 'video/mp4',
        size: 5,
      );
      final acik = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Açık', attachments: [var_, yok]);
      final gizli = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Gizli', attachments: [ozel]);
      await store.commit(acik);
      await store.commit(gizli);
      await store.setPrivate(gizli.id, true);

      expect(store.missingFiles(), {'files/yok.mp4': 5});
      expect(store.outgoingFile('files/var.pdf'), isNotNull);
      expect(store.outgoingFile('files/ozel.pdf'), isNull, reason: 'özel kaydın eki paylaşılmaz');
      expect(store.outgoingFile('files/../envanter.db'), isNull);

      // İndirme: boyutu tutmayan kabul edilmez, tutan yerine konur.
      final temp = store.incomingFile('files/yok.mp4')..writeAsBytesSync([1, 2, 3]);
      expect(await store.adoptFile('files/yok.mp4', temp), isFalse);
      expect(temp.existsSync(), isFalse);
      temp.writeAsBytesSync([1, 2, 3, 4, 5]);
      expect(await store.adoptFile('files/yok.mp4', temp), isTrue);
      expect(onDisk('files/yok.mp4'), isTrue);
      expect(store.missingFiles(), isEmpty);
      // Kimsenin beklemediği dosya yazılmaz.
      final stray = store.incomingFile('files/baska.pdf')..writeAsBytesSync([1]);
      expect(await store.adoptFile('files/baska.pdf', stray), isFalse);
      expect(onDisk('files/baska.pdf'), isFalse);
    });

    test('ek adıyla arama kaydı bulur', () async {
      final store = await device('ayse');
      final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Matkap',
            attachments: [fileOf('files/k.pdf', [1], name: 'Kullanım kılavuzu')],
          );
      await store.commit(n);
      expect(store.search('kilavuz').single.name, 'Matkap');
    });
  });

  test('kaplanan yer: diskteki dosyalar bir kez sayılır, inmemiş ek sayılmaz, en büyük ek başta', () async {
    final store = await device('ayse');
    File(AppPaths.abs('images/m.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(700, 1));
    AppPaths.forget('images/m.jpg');
    final video = fileOf('files/sorun.mp4', List.filled(5000, 2), name: 'Sorun videosu', mime: 'video/mp4');
    final kilavuz = fileOf('files/k.pdf', List.filled(1200, 3));
    final gelmedi = Attachment(
      id: 'y',
      name: 'Gelmedi',
      addedAt: DateTime.fromMillisecondsSinceEpoch(1),
      file: 'files/yok.mp4',
      mime: 'video/mp4',
      size: 999999,
    );
    final matkap = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
          name: 'Matkap',
          imagePath: 'images/m.jpg',
          attachments: [kilavuz, video, gelmedi],
        );
    // Aynı kılavuz iki kayıtta: bir kez sayılır.
    final testere = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Testere', attachments: [kilavuz]);
    final eski = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
          name: 'Eski',
          attachments: [fileOf('files/eski.pdf', List.filled(300, 4), name: 'Eski belge')],
        );
    await store.commit(matkap);
    await store.commit(testere);
    await store.commit(eski);
    // Kalıcı silinenin dosyası "Son silinenler"de durur: yer tutmaya devam eder.
    await store.deleteForever(eski.id);

    final usage = await store.measureStorage();
    expect(usage.photoCount, 1);
    expect(usage.photoBytes, 700);
    expect(usage.fileCount, 3, reason: 'video, kılavuz, arşivdeki belge');
    expect(usage.fileBytes, 5000 + 1200 + 300);
    expect(usage.totalBytes, 7200);
    expect(usage.largest.map((e) => e.attachment.name), ['Sorun videosu', 'Kılavuz']);
    expect(usage.largest.first.node.name, 'Matkap');
    expect(usage.largest.first.bytes, 5000);
  });

  test('yedek ekleri dosyalarıyla taşır', () async {
    final eski = await device('eski');
    final big = List<int>.generate(300000, (i) => i % 251);
    final n = eski.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
          name: 'Matkap',
          attachments: [
            fileOf('files/kilavuz.pdf', big),
            Attachment(
              id: 'l',
              name: 'Video',
              addedAt: DateTime.fromMillisecondsSinceEpoch(5),
              url: 'https://ornek.com/v',
            ),
          ],
        );
    await eski.commit(n);
    // İlerleme 0–1 arasında, hep ileri, sonunda 1.
    final writing = <double>[];
    final zip = await BackupService.export(eski, into: work, onProgress: writing.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(writing, isNotEmpty);
    expect(writing.last, 1.0);
    expect(writing, [...writing]..sort());
    await AppDatabase.instance.close();

    final yeni = await device('yeni');
    final reading = <double>[];
    final result = await BackupService.import(zip, yeni, onProgress: reading.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(reading.last, 1.0);
    expect(reading.every((v) => v >= 0 && v <= 1), isTrue);
    expect(result.added, 1);
    expect(result.files, 1);
    final back = yeni.byId(n.id)!;
    expect(back.attachments.map((a) => a.name), ['Video', 'Kılavuz'], reason: 'eklenme sırasıyla');
    expect(File(AppPaths.abs('files/kilavuz.pdf')).readAsBytesSync(), big);
    expect(yeni.missingFiles(), isEmpty, reason: 'yeni yazılan dosya hemen görülür');

    // Aynı yedek ikinci kez: dosya zaten var, yeniden yazılmaz.
    final again = await BackupService.import(zip, yeni);
    expect(again.files, 0);
    expect(again.added, 0);
  });

  test('yedek olmayan dosyada hata arka plandan olduğu gibi gelir', () async {
    final store = await device('ayse');
    final text = File('${work.path}/not.zip')..writeAsStringSync('zip değil');
    await expectLater(
      BackupService.import(text, store),
      throwsA(isA<BackupException>().having((e) => e.problem, 'problem', BackupProblem.notOurs)),
    );
  });
}
