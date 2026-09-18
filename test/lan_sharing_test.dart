import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:envanter/sync/fields.dart';

import 'package:envanter/sync/clock.dart';
import 'package:envanter/sync/discovery.dart';
import 'package:envanter/sync/lan_peer.dart';
import 'package:envanter/sync/sharing_config.dart';
import 'package:envanter/sync/sharing_service.dart';
import 'package:envanter/sync/wire.dart';
import 'package:envanter/data/node.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_inventory.dart';
import 'support/ports.dart';

Future<void> eventually(bool Function() condition, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) fail('koşul zamanında sağlanmadı');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late FakeInventory ayseInv;
  late FakeInventory aliInv;
  late SharingService ayse;
  late SharingService ali;
  late int basePort;

  SharingService device(String name, FakeInventory inv, int port, int peerPort) => SharingService(
        target: inv,
        configStore: MemorySharingConfigStore(),
        displayName: () => name,
        discovery: LanDiscovery(
          port: port,
          targets: [(InternetAddress.loopbackIPv4, peerPort)],
          interval: const Duration(milliseconds: 150),
          expiry: const Duration(milliseconds: 1500),
        ),
        debounce: const Duration(milliseconds: 100),
        periodic: const Duration(hours: 1),
        joinWait: const Duration(seconds: 3),
        resyncAfter: const Duration(milliseconds: 300),
      );

  setUp(() async {
    final base = await takePorts();
    basePort = base;
    ayseInv = FakeInventory();
    aliInv = FakeInventory();
    ayse = device('Ayşe', ayseInv, base, base + 1);
    ali = device('Ali', aliInv, base + 1, base);
    await ayse.load();
    await ali.load();
    // Bu testler eşitlemenin kendisini sınıyor; onay akışı ayrıca sınanıyor.
    await ayse.setAutoAccept(true);
    await ali.setAutoAccept(true);
  });

  tearDown(() async {
    await ayse.shutdown();
    await ali.shutdown();
    ayse.dispose();
    ali.dispose();
  });

  Future<void> joinAccepted() async {
    await ayse.setEnabled(true);
    await ali.setEnabled(true);
    await eventually(() => ali.joinableInventories.isNotEmpty);
    final request = ali.requestJoin(ali.joinableInventories.single);
    await eventually(() => ayse.pendingJoins.isNotEmpty);
    ayse.decideJoin(ayse.pendingJoins.single, true);
    expect(await request, JoinOutcome.accepted);
  }

  test('ortak kullanım varsayılan kapalı; kapalıyken ağda görünmez', () async {
    expect(ayse.enabled, isFalse);
    expect(ayse.running, isFalse);
    await ali.setEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(ali.joinableInventories, isEmpty);
  });

  test('açıkken envanter ağda adıyla görünür', () async {
    await ayse.rename('Ev');
    await ayse.setEnabled(true);
    await ali.setEnabled(true);
    await eventually(() => ali.joinableInventories.isNotEmpty);
    final seen = ali.joinableInventories.single.info;
    expect(seen.inventoryName, 'Ev');
    expect(seen.deviceName, 'Ayşe');
  });

  test('istek kabul edilince envanter ortak olur, iki taraftaki kayıtlar birleşir', () async {
    final mutfak = ayseInv.add('Mutfak', kind: NodeKind.container);
    ayseInv.add('Tencere', parent: mutfak.id, image: 'images/tencere.jpg');
    aliInv.add('Aliden kalan');

    await joinAccepted();

    await eventually(() => aliInv.named('Tencere') != null);
    expect(aliInv.files['images/tencere.jpg'], isNotNull, reason: 'foto da gelmeli');
    await eventually(() => ayseInv.named('Aliden kalan') != null);
    expect(ali.config.inventoryId, ayse.config.inventoryId);
    expect(ayse.config.members.map((m) => m.name), containsAll(['Ali']));
    expect(ali.config.isOwner, isFalse);
    expect(ali.joinableInventories, isEmpty, reason: 'artık aynı envanterdeler');
  });

  test('reddedilen istek erişim vermez', () async {
    ayseInv.add('Gizli');
    await ayse.setEnabled(true);
    await ali.setEnabled(true);
    await eventually(() => ali.joinableInventories.isNotEmpty);
    final request = ali.requestJoin(ali.joinableInventories.single);
    await eventually(() => ayse.pendingJoins.isNotEmpty);
    ayse.decideJoin(ayse.pendingJoins.single, false);

    expect(await request, JoinOutcome.rejected);
    expect(ali.config.inventoryId, isNot(ayse.config.inventoryId));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(aliInv.named('Gizli'), isNull);
  });

  test('yanıtlanmayan istek zamanla reddedilmiş sayılır', () async {
    await ayse.setEnabled(true);
    await ali.setEnabled(true);
    await eventually(() => ali.joinableInventories.isNotEmpty);
    final outcome = await ali.requestJoin(ali.joinableInventories.single);
    expect(outcome, JoinOutcome.rejected);
    expect(ayse.pendingJoins, isEmpty);
  });

  test('katıldıktan sonra değişiklikler iki yönde akar', () async {
    await joinAccepted();

    final raf = ayseInv.add('Raf', kind: NodeKind.container);
    await eventually(() => aliInv.named('Raf') != null);

    aliInv.add('Matkap', parent: raf.id, image: 'images/matkap.jpg');
    await eventually(() => ayseInv.named('Matkap') != null);
    await eventually(() => ayseInv.files['images/matkap.jpg'] != null);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    ayseInv.rename(raf.id, 'Üst raf');
    await eventually(() => aliInv.nodes[raf.id]?.name == 'Üst raf');
  });

  test('ek dosyaları iki yönde gelir: karşı cihaz eksik olanı kendisi çeker', () async {
    await joinAccepted();
    // Belleğe sığdırılmadan, parça parça gittiği görülsün diye birkaç MB.
    final manual = List<int>.generate(3 * 1024 * 1024 + 17, (i) => i % 253);
    // İnerken yüzdesi bildirilir (arayüz "iniyor, %40" yazar).
    final seen = <int>[];
    ali.fileProgress.addListener(() {
      if (ali.fileProgress.value['files/kilavuz.pdf'] case final p?) seen.add(p);
    });
    final matkap = ayseInv.add('Matkap');
    ayseInv.attach(matkap.id, 'files/kilavuz.pdf', manual, name: 'Kılavuz');
    await eventually(() => aliInv.named('Matkap')?.attachments.length == 1);
    await eventually(() => aliInv.fileBytes('files/kilavuz.pdf') != null);
    expect(aliInv.fileBytes('files/kilavuz.pdf'), manual);
    expect(aliInv.missingFiles(), isEmpty);
    expect(seen, isNotEmpty);
    expect(seen.last, 100);
    expect(seen, [...seen]..sort(), reason: 'yüzde hep ileri gider');
    expect(seen.toSet().length, seen.length, reason: 'aynı yüzde iki kez bildirilmez');
    await eventually(() => ali.fileProgress.value.isEmpty);

    // Ali'nin eklediği de Ayşe'ye gelir; ilk ek yerinde kalır.
    final ali2 = aliInv.named('Matkap')!;
    aliInv.attach(ali2.id, 'files/sorun.mp4', [7, 7, 7, 7], name: 'Sorun videosu');
    await eventually(() => ayseInv.fileBytes('files/sorun.mp4') != null);
    expect(ayseInv.fileBytes('files/sorun.mp4'), [7, 7, 7, 7]);
    expect(ayseInv.named('Matkap')!.attachments.map((a) => a.name), ['Kılavuz', 'Sorun videosu']);
  });

  test('iki cihaz aynı kayda aynı anda ek koyarsa ikisi de kalır; çıkarılan ek iki tarafta da kalkar', () async {
    await joinAccepted();
    final matkap = ayseInv.add('Matkap');
    await eventually(() => aliInv.named('Matkap') != null);

    // Eşitlenmeyi beklemeden, art arda: eskiden son yazanın listesi kalır, ötekinin eki kaybolurdu.
    final kilavuz = ayseInv.attach(matkap.id, 'files/kilavuz.pdf', [1, 2, 3], name: 'Kılavuz');
    aliInv.attach(matkap.id, 'files/garanti.jpg', [4, 5], name: 'Garanti');
    Set<String> names(FakeInventory inv) => {for (final a in inv.nodes[matkap.id]!.attachments) a.name};
    await eventually(() => names(ayseInv).length == 2 && names(aliInv).length == 2);
    expect(names(ayseInv), {'Kılavuz', 'Garanti'});
    expect(names(aliInv), {'Kılavuz', 'Garanti'});
    await eventually(() => aliInv.fileBytes('files/kilavuz.pdf') != null && ayseInv.fileBytes('files/garanti.jpg') != null);
    expect(ayseInv.fileBytes('files/garanti.jpg'), [4, 5]);

    // Ali kılavuzu çıkarır: Ayşe'de de kalkar, garanti durur.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    aliInv.update(matkap.id, (n) => n.copyWith(attachments: [for (final a in n.attachments) if (a.id != kilavuz.id) a]));
    await eventually(() => names(ayseInv).length == 1);
    expect(names(ayseInv), {'Garanti'});
    expect(ayseInv.nodes[matkap.id]!.attachmentTombs.keys, [kilavuz.id]);
  });

  group('büyük durum ayrı yalıtımda', () {
    late int nodes;
    late int bytes;

    setUp(() {
      nodes = stateOffloadNodes;
      bytes = stateOffloadBytes;
      stateOffloadCount = 0;
    });

    tearDown(() {
      stateOffloadNodes = nodes;
      stateOffloadBytes = bytes;
    });

    SyncState big(int count) {
      final t = DateTime.fromMillisecondsSinceEpoch(1790000000000);
      return SyncState(
        nodes: {
          for (var i = 0; i < count; i++)
            'n$i': stampChanges(
              null,
              Node(
                id: 'n$i',
                parentId: i == 0 ? null : 'n0',
                kind: i == 0 ? NodeKind.container : NodeKind.item,
                name: 'Kayıt $i',
                color: 0xFF3F6C8C,
                sortIndex: i.toDouble(),
                createdAt: t,
                updatedAt: t,
                note: i.isEven ? 'şğüöçı notu' : null,
                barcode: i % 7 == 0 ? '8690000$i' : null,
              ),
              t,
            ),
        },
        tombstones: const {'silinmis': 5},
        members: const [],
        from: 'ayse',
      );
    }

    test('kodlama ve çözme yalıtımda da yerindekiyle aynı sonucu verir; eşiğin altında yalıtım açılmaz', () async {
      final state = big(600);
      stateOffloadNodes = 1 << 30;
      stateOffloadBytes = 1 << 30;
      final here = await encodeState(state);
      expect(stateOffloadCount, 0);
      expect(here.digest, sha256.convert(here.body).toString());

      stateOffloadNodes = 400;
      stateOffloadBytes = 1024;
      final off = await encodeState(state);
      expect(stateOffloadCount, 1, reason: '600 kayıt eşiğin üstünde');
      expect(off.body, here.body);
      expect(off.digest, here.digest);

      final decoded = (await decodeState(off.body))!;
      expect(stateOffloadCount, 2);
      expect(decoded.nodes.length, 600);
      expect(decoded.nodes['n4']!.note, 'şğüöçı notu');
      expect(decoded.nodes['n7']!.barcode, '86900007');
      expect(decoded.tombstones, {'silinmis': 5});
      expect(
        stateStampOf(decoded.nodes.values, decoded.tombstones),
        stateStampOf(state.nodes.values, state.tombstones),
        reason: 'yalıtımdan dönen kayıtlar aynı içerikte',
      );
      expect(await decodeState(utf8.encode('{"nodes": 5}')), isNull);
      expect(await decodeState(Uint8List.fromList(List.filled(4000, 0xFF))), isNull, reason: 'bozuk gövde de yalıtımdan null döner');
    });

    test('imzası tutmayan gövde çözülmez; tutan, istenirse çözülür', () async {
      stateOffloadBytes = 1024;
      final key = RequestSigner.newKey();
      final signer = RequestSigner(key);
      final encoded = await encodeState(big(50));
      final now = DateTime.now();
      final headers = signer.headers('POST', '/state', encoded.body, now, digest: encoded.digest);
      expect(headers, signer.headers('POST', '/state', encoded.body, now), reason: 'hazır özetle imza aynı');
      Future<(bool, SyncState?)> check({List<int>? withKey, String? signature, bool decode = true}) => verifyAndDecodeState(
            key: withKey ?? key,
            method: 'POST',
            path: '/state',
            body: encoded.body,
            time: headers[RequestSigner.timeHeader],
            signature: signature ?? headers[RequestSigner.signatureHeader],
            now: now,
            decode: decode,
          );

      final (ok, state) = await check();
      expect(ok, isTrue);
      expect(state!.nodes.length, 50);
      expect(stateOffloadCount, greaterThan(0));
      expect(await check(withKey: RequestSigner.newKey()), (false, null));
      expect(await check(signature: 'a' * 64), (false, null));
      expect(await check(decode: false), (true, null), reason: 'sürümü farklı ya da çıkarılmış cihazın gövdesi çözülmez');
    });

    test('iki cihaz her şeyi yalıtım yoluyla eşitler: katılma, değişiklik, ek, silme', () async {
      stateOffloadNodes = 0;
      stateOffloadBytes = 0;
      final kutu = ayseInv.add('Kutu', kind: NodeKind.container);
      for (var i = 0; i < 40; i++) {
        ayseInv.add('Eşya $i', parent: kutu.id);
      }
      await joinAccepted();
      await eventually(() => aliInv.nodes.length == 41);
      expect(stateOffloadCount, greaterThan(2), reason: 'gövdeler yalıtımda kodlandı, doğrulandı, çözüldü');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      aliInv.rename(kutu.id, 'Büyük kutu');
      await eventually(() => ayseInv.nodes[kutu.id]?.name == 'Büyük kutu');
      ayseInv.attach(kutu.id, 'files/liste.pdf', [1, 2, 3, 4], name: 'Liste');
      await eventually(() => aliInv.fileBytes('files/liste.pdf') != null);
      final one = aliInv.named('Eşya 7')!;
      aliInv.purge(one.id);
      await eventually(() => ayseInv.named('Eşya 7') == null);
      expect(ayseInv.nodes.length, 40);
    });
  });

  test('ek dosyası imzasız istenemez; kayıtlarda geçmeyen dosya verilmez', () async {
    await joinAccepted();
    final matkap = ayseInv.add('Matkap');
    ayseInv.attach(matkap.id, 'files/kilavuz.pdf', [1, 2, 3]);
    final base = ali.onlineMembers.single.baseUri;
    final http = HttpClient();
    addTearDown(() => http.close(force: true));
    final unsigned = await (await http.getUrl(base.replace(path: '/file/files%2Fkilavuz.pdf'))).close();
    await unsigned.drain<void>();
    expect(unsigned.statusCode, HttpStatus.unauthorized);

    final temp = File('${Directory.systemTemp.createTempSync('envanter_ek').path}/x.part');
    final client = PeerClient(
      base,
      signer: RequestSigner(ayse.config.key),
      from: ali.config.deviceId,
    );
    addTearDown(client.close);
    expect(await client.downloadFile('files/baska.pdf', temp, limit: 100), isFalse, reason: 'hiçbir kaydın eki değil');
    expect(await client.downloadFile('files/kilavuz.pdf', temp, limit: 100), isTrue);
    expect(temp.readAsBytesSync(), [1, 2, 3]);
    // Beklenenden büyük yanıt yarıda kesilir.
    await expectLater(client.downloadFile('files/kilavuz.pdf', temp, limit: 2), throwsA(isA<PeerException>()));
  });

  test('aynı anda farklı alanları değiştiren iki cihaz ikisini birden tutar', () async {
    final pil = ayseInv.add('Pil');
    await joinAccepted();
    await eventually(() => aliInv.named('Pil') != null);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Arada eşitleme olmadan: ikisi de kaydın aynı sürümünü değiştiriyor.
    aliInv.update(pil.id, (n) => n.copyWith(name: 'Kalem pil'), by: 'ali');
    ayseInv.update(pil.id, (n) => n.copyWith(quantity: 3), by: 'ayse');

    bool both(FakeInventory inv) => inv.nodes[pil.id]?.name == 'Kalem pil' && inv.nodes[pil.id]?.quantity == 3;
    await eventually(() => both(ayseInv) && both(aliInv));
    await eventually(() => ayseInv.stateStamp == aliInv.stateStamp);
  });

  group('üyelikten çıkma', () {
    test('ana kullanıcı üyeyi çıkarır; çıkarılan cihaz öğrenir, kayıtları kalır', () async {
      await joinAccepted();
      final raf = ayseInv.add('Raf', kind: NodeKind.container);
      await eventually(() => aliInv.named('Raf') != null);
      final aliId = ali.config.deviceId;
      final removedFrom = <String>[];
      final sub = ali.removedEvents.listen(removedFrom.add);

      expect(await ayse.removeMember(aliId), isTrue);
      expect(ayse.config.isMember(aliId), isFalse);
      await eventually(() => !ali.config.isShared);
      await eventually(() => removedFrom.isNotEmpty);
      expect(aliInv.nodes.containsKey(raf.id), isTrue, reason: 'kayıtlar onda kalır');
      expect(ali.config.inventoryId, isNot(ayse.config.inventoryId));

      // Artık eşitlenmez.
      ayseInv.add('Kutu');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(aliInv.named('Kutu'), isNull);
      await sub.cancel();

      // Yeniden katılmak isterse onaya düşer; kabul edilince çıkarılma izine rağmen üyedir.
      final request = ali.requestJoin(ali.joinableInventories.single);
      await eventually(() => ayse.pendingJoins.isNotEmpty);
      ayse.decideJoin(ayse.pendingJoins.single, true);
      expect(await request, JoinOutcome.accepted);
      await eventually(() => aliInv.named('Kutu') != null);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(ayse.config.isMember(aliId), isTrue);
      expect(ali.config.isMember(aliId), isTrue);
    });

    test('ana kullanıcı olmayan çıkaramaz, ana kullanıcı çıkarılamaz', () async {
      await joinAccepted();
      expect(await ali.removeMember(ayse.config.deviceId), isFalse);
      await ayse.setAdmin(ali.config.deviceId, true);
      expect(await ayse.removeMember(ali.config.deviceId), isFalse);
    });

    test('üye kendi isteğiyle ayrılır; sahibin listesinden düşer', () async {
      await joinAccepted();
      final aliId = ali.config.deviceId;
      await eventually(() => ayse.onlineMembers.isNotEmpty);
      await ali.leave();
      expect(ali.config.isShared, isFalse);
      await eventually(() => !ayse.config.isMember(aliId));
      expect(ayse.config.isShared, isFalse);
    });

    test('yönetici envanteri silince yönetim seçtiği kişiye geçer; herkese haber gider', () async {
      await joinAccepted();
      final ayseId = ayse.config.deviceId;
      final aliId = ali.config.deviceId;
      final events = <GovernanceEvent>[];
      final sub = ali.governanceEvents.listen(events.add);
      await eventually(() => ayse.onlineMembers.isNotEmpty);
      await ayse.leave(newOwner: aliId, deleted: true);
      await eventually(() => !ali.config.isMember(ayseId));
      await eventually(() => ali.config.isOwner);
      expect(ali.config.isAdmin, isTrue, reason: 'katılma isteklerini artık o onaylar');
      expect(ali.config.isAdminDevice(ayseId), isFalse);
      await eventually(() => events.any((e) => e.newOwner == aliId) && events.any((e) => e.deleted));
      expect(events.firstWhere((e) => e.newOwner == aliId).previousOwner, 'Ayşe');
      expect(events.firstWhere((e) => e.deleted).leftName, 'Ayşe');
      await sub.cancel();
    });

    test('yönetici varis seçer; varis yönetici ayrılınca kendiliğinden yönetici olur', () async {
      await joinAccepted();
      final ayseId = ayse.config.deviceId;
      final aliId = ali.config.deviceId;
      final events = <GovernanceEvent>[];
      final sub = ali.governanceEvents.listen(events.add);
      expect(await ali.setHeir(ayseId), isFalse, reason: 'yalnızca yönetici varis seçer');
      expect(await ayse.setHeir(aliId), isTrue);
      await eventually(() => ali.config.isHeir);
      await eventually(() => events.any((e) => e.heirToMe));
      expect(ali.config.isAdmin, isTrue, reason: 'varis ana kullanıcı yetkisinde');
      expect(await ali.setHeir(ayseId), isFalse, reason: 'varis, yönetici olana dek varis seçemez');

      // Yönetici kimseyi seçmeden ayrılırsa varise geçer.
      await eventually(() => ayse.onlineMembers.isNotEmpty);
      await ayse.leave();
      await eventually(() => ali.config.isOwner);
      expect(ali.config.heir, isNull);
      expect(await ali.setHeir(ayseId), isFalse, reason: 'ayrılan kişi varis olamaz');
      await sub.cancel();
    });

    test('yöneticiliği devreden otomatik varis olur; varis ayrılınca varislik boşalır', () async {
      await joinAccepted();
      final ayseId = ayse.config.deviceId;
      final aliId = ali.config.deviceId;
      expect(await ayse.transferOwnership(aliId), isTrue);
      await eventually(() => ali.config.isOwner);
      expect((ayse.config.ownerDeviceId, ayse.config.heir), (aliId, ayseId));
      expect((ali.config.ownerDeviceId, ali.config.heir), (aliId, ayseId));
      expect(ayse.config.isAdmin, isTrue, reason: 'varis olarak yetkisi sürer');

      await eventually(() => ayse.onlineMembers.isNotEmpty);
      await ayse.leave();
      await eventually(() => !ali.config.isMember(ayseId));
      expect(ali.config.heir, isNull);
      expect(ali.config.isOwner, isTrue);
    });
  });

  test('geri çevrilen değişikliğin haberi yapana bir kez ulaşır; ötekine gösterilmez', () async {
    await joinAccepted();
    final aliId = ali.config.deviceId;
    final toAli = <List<Notice>>[];
    final toAyse = <List<Notice>>[];
    final s1 = ali.noticeEvents.listen(toAli.add);
    final s2 = ayse.noticeEvents.listen(toAyse.add);
    await eventually(() => ayse.onlineMembers.isNotEmpty);
    await ayse.addNotices([
      Notice(
        id: 'n1',
        to: aliId,
        by: ayse.config.deviceId,
        name: 'Kalem',
        kind: 'edited',
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
    await eventually(() => toAli.isNotEmpty);
    expect(toAli.single.single.name, 'Kalem');
    expect(ayse.memberName(toAli.single.single.by), 'Ayşe');
    await ali.syncNow();
    await ayse.syncNow();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(toAli, hasLength(1), reason: 'bir kez');
    expect(toAyse, isEmpty);
    expect(ali.config.notices.single.id, 'n1', reason: 'haber herkeste durur, yayılabilsin');
    await s1.cancel();
    await s2.cancel();
  });

  group('saat', () {
    tearDown(() => SyncClock.restore(auto: true));

    test('saati otomatik olmayan telefon, otomatik olanın saatine göre düzeltilir ve uyarılır', () async {
      // Ayşe'nin saati otomatik ve bizimkinden 10 dakika ileri; Ali'ninki (bu süreç) elle ayarlı.
      await ayse.shutdown();
      ayse.dispose();
      ayse = SharingService(
        target: ayseInv,
        configStore: MemorySharingConfigStore(),
        displayName: () => 'Ayşe',
        discovery: LanDiscovery(
          port: basePort,
          targets: [(InternetAddress.loopbackIPv4, basePort + 1)],
          interval: const Duration(milliseconds: 150),
          expiry: const Duration(milliseconds: 1500),
        ),
        debounce: const Duration(milliseconds: 100),
        periodic: const Duration(hours: 1),
        joinWait: const Duration(seconds: 3),
        resyncAfter: const Duration(milliseconds: 300),
        clock: () => DateTime.now().add(const Duration(minutes: 10)),
        clockTrusted: () => true,
      );
      await ayse.load();
      await ayse.setAutoAccept(true);
      SyncClock.restore(auto: false);
      final events = <ClockEvent>[];
      final sub = ali.clockEvents.listen(events.add);
      await joinAccepted();
      await eventually(() => events.isNotEmpty);
      expect(events.single.mineWrong, isTrue);
      expect(events.single.skewMs, closeTo(600000, 5000));
      expect(SyncClock.offsetMs, closeTo(600000, 5000), reason: 'bundan sonra düzeltilmiş saatle damgalanır');
      expect(SyncClock.now().difference(DateTime.now()).inMilliseconds, closeTo(600000, 5000));
      expect(ali.clockIssue(ayse.config.deviceId)?.mineWrong, isTrue);
      await sub.cancel();
    });

    test('saati otomatik telefon düzeltmez; küçük farklar da görmezden gelinir', () {
      SyncClock.restore(auto: true);
      expect(SyncClock.adopt(600000), isFalse);
      expect(SyncClock.offsetMs, 0);
      SyncClock.restore(auto: false);
      expect(SyncClock.adopt(5000), isFalse, reason: 'ağ gecikmesi kadar');
      expect(SyncClock.adopt(-600000), isTrue);
      expect(SyncClock.now().isBefore(DateTime.now()), isTrue);
    });

    test('saat durumla birlikte gider', () {
      final state = SyncState.fromJson(jsonDecode(jsonEncode(
        const SyncState(nodes: {}, tombstones: {}, members: [], clock: 123, clockTrusted: true).toJson(),
      )));
      expect((state.clock, state.clockTrusted), (123, true));
    });

    /// Ayşe'nin telefonu: saati bu süreçtekinden [ahead] ileri (imzalar da o saatle atılır).
    Future<void> ayseAhead(Duration ahead) async {
      await ayse.shutdown();
      ayse.dispose();
      ayse = SharingService(
        target: ayseInv,
        configStore: MemorySharingConfigStore(),
        displayName: () => 'Ayşe',
        discovery: LanDiscovery(
          port: basePort,
          targets: [(InternetAddress.loopbackIPv4, basePort + 1)],
          interval: const Duration(milliseconds: 150),
          expiry: const Duration(milliseconds: 1500),
        ),
        debounce: const Duration(milliseconds: 100),
        periodic: const Duration(hours: 1),
        joinWait: const Duration(seconds: 3),
        resyncAfter: const Duration(milliseconds: 300),
        clock: () => DateTime.now().add(ahead),
        clockTrusted: () => true,
      );
      await ayse.load();
      await ayse.setAutoAccept(true);
    }

    test('saatleri 5 dakikadan çok farklı iki telefon da eşitlenir', () async {
      // İmzalar ±5 dakikalık pencerenin dışında kalıyordu: katılma imzasız olduğu için oluyor,
      // envanter iki yöne de hiç gitmiyordu. Artık imza karşının bildirdiği saate göre yeniden atılır.
      SyncClock.restore(auto: true);
      await ayseAhead(const Duration(minutes: 10));
      ayseInv.add('Tencere');
      aliInv.add('Aliden kalan');
      await joinAccepted();
      await eventually(() => aliInv.named('Tencere') != null);
      await eventually(() => ayseInv.named('Aliden kalan') != null);
      expect(ali.clockIssue(ayse.config.deviceId), isNotNull, reason: 'saat farkı artık görünebiliyor');
      // Öğrenilen fark saklanır: sonraki değişiklik de gider.
      ayseInv.add('Kahve makinesi');
      await eventually(() => aliInv.named('Kahve makinesi') != null);
    });

    test('anahtar tutmuyorsa saat farkında da bir kez yeniden denenir, istek reddedilir', () async {
      SyncClock.restore(auto: true);
      await ayseAhead(const Duration(minutes: 10));
      await ayse.setEnabled(true);
      await ali.setEnabled(true);
      await eventually(() => ali.joinableInventories.isNotEmpty);
      final client = PeerClient(
        ali.joinableInventories.single.baseUri,
        signer: RequestSigner(RequestSigner.newKey()),
      );
      addTearDown(client.close);
      await expectLater(
        client.getState(),
        throwsA(isA<PeerException>().having((e) => e.unauthorized, 'unauthorized', isTrue)),
      );
      expect(client.timeShift.inSeconds, closeTo(600, 5), reason: 'saat farkı öğrenildi, ama anahtar yine tutmadı');
    });
  });

  test('eski haberler düşer; haberler kimliğe göre tek', () {
    final now = DateTime(2026, 10, 1);
    Notice n(String id, DateTime at) => Notice(id: id, to: 'a', by: 'b', name: 'x', kind: 'edited', at: at.millisecondsSinceEpoch);
    final merged = mergeNotices(
      [n('1', now), n('eski', now.subtract(const Duration(days: 15)))],
      [n('1', now), n('2', now.subtract(const Duration(days: 1)))],
      now,
    );
    expect(merged.map((x) => x.id), ['1', '2']);
    expect(Notice.fromJson({'id': 'x', 'to': 'a', 'by': 'b', 'name': 'x', 'kind': '<script>', 'at': 1}), isNull);
  });

  test('arka plandaki kısa eşitleme turu: ağ açılır, eşitlenir, eski haline döner', () async {
    await joinAccepted();
    await eventually(() => aliInv.named('Tencere') == null && ali.onlineMembers.isNotEmpty);
    // Ali'nin uygulaması arka planda: ağ kapalı.
    await ali.pause();
    expect(ali.running, isFalse);
    ayseInv.add('Tencere');
    final synced = await ali.syncRound(window: const Duration(seconds: 8));
    expect(synced, 1);
    expect(aliInv.named('Tencere'), isNotNull);
    expect(ali.running, isFalse, reason: 'tur bitince yine arka planda');
    await ali.resume();
    expect(ali.running, isTrue);
  });

  test('arka plan turu sürerken uygulama öne gelirse ortak kullanım açık kalır', () async {
    await joinAccepted();
    await eventually(() => ali.onlineMembers.isNotEmpty && !ali.syncing);
    // Ali'nin uygulaması arka planda; Ayşe ağda değil: tur pencerenin sonuna kadar sürer.
    await ali.pause();
    await ayse.pause();
    final round = ali.syncRound(window: const Duration(seconds: 2));
    await eventually(() => ali.running);
    // Kullanıcı tur sürerken uygulamayı açar.
    await ali.resume();
    await round;
    expect(ali.running, isTrue, reason: 'tur bitince ağ kapanmaz: uygulama artık önde');
  });

  test('paylaşılmayan envanterde eşitleme turu hiçbir şey açmaz', () async {
    await ali.setEnabled(true);
    expect(await ali.syncRound(window: const Duration(seconds: 1)), 0);
  });

  test('eşitleme olmazsa nedeni üyede durur; eşitlenince düşer', () async {
    ayseInv.add('Tencere');
    await joinAccepted();
    final id = ayse.config.deviceId;
    await eventually(() => aliInv.named('Tencere') != null && !ali.syncing);
    expect(ali.failureWith(id), isNull);
    // Ayşe'nin sunucusu kapandı, duyurusu Ali'de henüz düşmedi: Ali'nin yeni kaydı gidemez.
    await ayse.pause();
    aliInv.add('Pil');
    await eventually(() => ali.failureWith(id) == SyncFailure.unreachable);
    // Ayşe döndüğünde Ali'yle yeniden eşitlesin diye son eşitlemelerinden beri resyncAfter geçmeli.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await ayse.resume();
    await eventually(() => ayseInv.named('Pil') != null);
    await eventually(() => ali.failureWith(id) == null);
  });

  test('üyeyle en son eşitlenme anı saklanır', () async {
    await joinAccepted();
    await eventually(() => ali.config.syncedWith.containsKey(ayse.config.deviceId));
    await eventually(() => ayse.config.syncedWith.containsKey(ali.config.deviceId));
  });

  test('kalıcı silme karşıya da yansır', () async {
    final kutu = ayseInv.add('Kutu');
    await joinAccepted();
    await eventually(() => aliInv.named('Kutu') != null);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    ayseInv.purge(kutu.id);
    await eventually(() => aliInv.named('Kutu') == null);
  });

  test('imzasız ya da yanlış anahtarla istek reddedilir', () async {
    await ayse.setEnabled(true);
    await ali.setEnabled(true);
    await eventually(() => ali.joinableInventories.isNotEmpty);
    final uri = ali.joinableInventories.single.baseUri.replace(path: '/state');

    final client = HttpClient();
    final plain = await (await client.getUrl(uri)).close();
    expect(plain.statusCode, HttpStatus.unauthorized);
    client.close(force: true);
  });

  test('ortak kullanım kapatılınca cihaz ağdan düşer', () async {
    await ayse.setEnabled(true);
    await ali.setEnabled(true);
    await eventually(() => ali.joinableInventories.isNotEmpty);
    await ayse.setEnabled(false);
    await eventually(() => ali.joinableInventories.isEmpty);
    expect(ayse.running, isFalse);
  });

  test('ortaklıktan ayrılan cihaz kayıtlarını korur ama artık eşitlenmez', () async {
    ayseInv.add('Ortak eşya');
    await joinAccepted();
    await eventually(() => aliInv.named('Ortak eşya') != null);

    await ali.leave();
    expect(ali.config.isOwner, isTrue);
    expect(ali.config.inventoryId, isNot(ayse.config.inventoryId));
    ayseInv.add('Sonradan eklenen');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(aliInv.named('Ortak eşya'), isNotNull);
    expect(aliInv.named('Sonradan eklenen'), isNull);
  });

  group('onaylı mod (varsayılan)', () {
    setUp(() async {
      await ayse.setAutoAccept(false);
      await ali.setAutoAccept(false);
    });

    test('varsayılan olarak değişiklikler onaya düşer', () async {
      final fresh = SharingConfig.fresh();
      expect(fresh.autoAccept, isFalse);
      expect(SharingConfig.fromJson(fresh.toJson())!.autoAccept, isFalse);
    });

    test('katılan cihaza ortak envanter onaysız gelir, sahibe katılanın kayıtları onaya düşer', () async {
      ayseInv.add('Dolap', kind: NodeKind.container);
      aliInv.add('Bisiklet');
      await joinAccepted();
      expect(aliInv.named('Dolap'), isNotNull, reason: 'katılırken ilk eşitleme doğrudan');
      await eventually(() => ayseInv.reviewed.isNotEmpty);
      expect(ayseInv.named('Bisiklet'), isNull, reason: 'sahipte onay bekliyor');
      final incoming = ayseInv.reviewed.last;
      expect(incoming.nodes.values.any((n) => n.name == 'Bisiklet'), isTrue);
      expect(incoming.from, ali.config.deviceId);
    });

    test('katıldıktan sonraki değişiklikler karşıda beklemeye alınır', () async {
      final dolap = ayseInv.add('Dolap', kind: NodeKind.container);
      await joinAccepted();
      aliInv.reviewed.clear();
      ayseInv.rename(dolap.id, 'Gardırop');
      await eventually(() => aliInv.reviewed.any((r) => r.nodes[dolap.id]?.name == 'Gardırop'));
      expect(aliInv.nodes[dolap.id]!.name, 'Dolap');
      expect(aliInv.reviewed.last.from, ayse.config.deviceId);
    });

    test('isim, gönderen cihaz kimliğinden bulunur', () async {
      await joinAccepted();
      expect(ayse.memberName(ali.config.deviceId), 'Ali');
      expect(ali.memberName(ayse.config.deviceId), 'Ayşe');
      expect(ali.memberName(ali.config.deviceId), 'Ali');
    });
  });

  group('roller', () {
    test('sahip bir üyeyi ana kullanıcı yapar; rol karşıya geçer, üye de istek kabul edebilir', () async {
      await joinAccepted();
      expect(ali.config.isAdmin, isFalse);
      expect(await ali.setAdmin(ayse.config.deviceId, false), isFalse, reason: 'üye rol veremez');

      expect(await ayse.setAdmin(ali.config.deviceId, true), isTrue);
      await eventually(() => ali.config.isAdmin);
      expect(ayse.isAdminDevice(ali.config.deviceId), isTrue);
      expect(await ali.setAdmin(ayse.config.deviceId, false), isFalse, reason: 'sahibin yetkisi alınmaz');
      expect(ali.config.isOwner, isFalse, reason: 'sahiplik değişmez');
    });

    test('yetki geri alınınca üyeye de yansır', () async {
      await joinAccepted();
      await ayse.setAdmin(ali.config.deviceId, true);
      await eventually(() => ali.config.isAdmin);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await ayse.setAdmin(ali.config.deviceId, false);
      await eventually(() => !ali.config.isAdmin);
    });

    test('rol bilgisi gidiş dönüşte korunur', () {
      const m = Member(deviceId: 'a', name: 'Ayşe', admin: true, roleAt: 42);
      final back = Member.fromJson(m.toJson())!;
      expect(back.admin, isTrue);
      expect(back.roleAt, 42);
      expect(Member.fromJson({'deviceId': 'b', 'name': 'Eski'})!.admin, isFalse);
    });
  });

  group('istek üzerine tarama', () {
    test('seyrek duyuruda bile tarama karşı envanteri hemen bulur', () async {
      final base = await takePorts();
      // Duyurular çok seyrek: yalnızca soru-yanıt ile bulunabilir.
      LanDiscovery slow(int port, int peer) => LanDiscovery(
            port: port,
            targets: [(InternetAddress.loopbackIPv4, peer)],
            interval: const Duration(minutes: 5),
            expiry: const Duration(minutes: 10),
          );
      final a = SharingService(
        target: FakeInventory(),
        configStore: MemorySharingConfigStore(),
        displayName: () => 'Ayşe',
        discovery: slow(base, base + 1),
      );
      final b = SharingService(
        target: FakeInventory(),
        configStore: MemorySharingConfigStore(),
        displayName: () => 'Ali',
        discovery: slow(base + 1, base),
      );
      addTearDown(() async {
        await a.shutdown();
        await b.shutdown();
      });
      await a.load();
      await b.load();
      await a.rename('Ev');
      await a.setEnabled(true);
      await b.setEnabled(true);

      expect(b.lastScanAt, isNull, reason: 'kendiliğinden taranmaz');
      final scan = b.scan(window: const Duration(seconds: 2));
      expect(b.scanning, isTrue);
      await scan;
      expect(b.scanning, isFalse);
      expect(b.lastScanAt, isNotNull);
      expect(b.joinableInventories.map((p) => p.info.inventoryName), ['Ev']);
    });
  });

  group('farklı sürümdeki uygulamalar', () {
    /// Ali'nin elindeki anahtarla, eski bir uygulama gibi (ya da verilen veri
    /// sürümüyle) Ayşe'nin sunucusuna doğrudan istek.
    Future<(int, String)> raw(String method, {int? data, List<int> body = const []}) async {
      final uri = ali.onlineMembers.single.baseUri.replace(path: '/state');
      final http = HttpClient();
      try {
        final req = await http.openUrl(method, uri);
        RequestSigner(ali.config.key).headers(method, '/state', body, DateTime.now()).forEach(req.headers.set);
        req.headers.set(kFromHeader, ali.config.deviceId);
        if (data != null) req.headers.set(kDataHeader, '$data');
        if (body.isNotEmpty) {
          req.contentLength = body.length;
          req.add(body);
        }
        final res = await req.close();
        return (res.statusCode, await res.transform(utf8.decoder).join());
      } finally {
        http.close(force: true);
      }
    }

    test('eski uygulama ne durumu alır ne verir; kim güncellemeli bilinir', () async {
      ayseInv.add('Süt');
      await joinAccepted();
      await eventually(() => aliInv.named('Süt') != null);
      await eventually(() => ali.onlineMembers.isNotEmpty);

      // Sürüm başlığı olmayan (eski) uygulama durumu isteyemez.
      final (status, body) = await raw('GET');
      expect(status, HttpStatus.upgradeRequired);
      expect(body, isNot(contains('Süt')), reason: 'kayıtlar verilmedi');
      expect(ayse.incompatibleVersion(ali.config.deviceId), 0);

      // Eski uygulamanın ittiği (tarihleri atılmış) durum da alınmaz.
      final stripped = SyncState(
        nodes: {for (final n in aliInv.nodes.values) n.id: n.copyWith(name: 'Eski sürümden')},
        tombstones: const {},
        members: const [],
        from: ali.config.deviceId,
        dataVersion: 11,
      );
      final (postStatus, _) = await raw('POST', data: 11, body: utf8.encode(jsonEncode(stripped.toJson())));
      expect(postStatus, HttpStatus.upgradeRequired);
      expect(ayseInv.named('Eski sürümden'), isNull);
      expect(ayse.incompatibleVersion(ali.config.deviceId), 11);

      // Aynı sürümle konuşunca işaret kalkar.
      final (ok, _) = await raw('GET', data: kDataVersion);
      expect(ok, HttpStatus.ok);
      await ayse.syncNow();
      await eventually(() => ayse.incompatibleVersion(ali.config.deviceId) == null);
    });

    test('duyuruda ve durumda sürüm yoksa eski uygulama sayılır', () {
      final old = Announcement.fromJson({
        'app': 'envanter',
        'v': 1,
        'deviceId': 'eski',
        'inventoryId': 'env',
        'port': 4000,
      })!;
      expect(old.dataVersion, 0);
      expect(SyncState.fromJson({'nodes': [], 'tombstones': {}, 'members': []}).dataVersion, 0);
      expect(SyncState.fromJson(const SyncState(nodes: {}, tombstones: {}, members: []).toJson()).dataVersion,
          kDataVersion);
    });
  });

  test('güvenlik: üye kimliğini taklit eden yabancıya anahtar verilmez', () async {
    await joinAccepted();
    // Duyurular imzasız: ağdaki bir yabancı üyelerin kimliğini okuyabilir.
    // O kimlikle katılmaya çalışırsa anahtar doğrudan verilmemeli.
    final owner = ali.onlineMembers.firstWhere((p) => p.info.deviceId == ayse.config.deviceId);
    final stranger = PeerClient(owner.baseUri);
    try {
      final attempt = stranger.join(deviceId: ali.config.deviceId, name: 'Yabancı');
      await eventually(() => ayse.pendingJoins.isNotEmpty, timeout: const Duration(seconds: 3));
      ayse.decideJoin(ayse.pendingJoins.single, false);
      expect(await attempt, isNull, reason: 'onay olmadan anahtar verilmez');
    } finally {
      stranger.close();
    }
  });

  test('güvenlik: envanter kimliğini duyuran yabancı üye sayılmaz', () async {
    await joinAccepted();
    // Duyurular imzasız: ağdaki bir cihaz envanter kimliğini okuyup kendini
    // o envanterin üyesiymiş gibi duyurabilir. Görülür ama üye sayılmaz;
    // durumumuz ona gönderilmez.
    final store = MemorySharingConfigStore()
      ..value = SharingConfig(
        enabled: true,
        deviceId: 'yabanci',
        inventoryId: ayse.config.inventoryId,
        inventoryName: 'Taklit',
        ownerDeviceId: 'yabanci',
        key: RequestSigner.newKey(),
        members: const [Member(deviceId: 'yabanci', name: 'Yabancı')],
      );
    final stranger = SharingService(
      target: FakeInventory(),
      configStore: store,
      displayName: () => 'Yabancı',
      discovery: LanDiscovery(
        port: basePort + 5,
        targets: [(InternetAddress.loopbackIPv4, basePort)],
        interval: const Duration(milliseconds: 150),
        expiry: const Duration(milliseconds: 1500),
      ),
      debounce: const Duration(milliseconds: 100),
      periodic: const Duration(hours: 1),
    );
    await stranger.load();
    try {
      await eventually(
        () => ayse.discovery.peers.any((p) => p.info.deviceId == 'yabanci'),
        timeout: const Duration(seconds: 5),
      );
      expect(
        ayse.onlineMembers.any((p) => p.info.deviceId == 'yabanci'),
        isFalse,
        reason: 'kabul edilmemiş cihaz üye sayılmaz',
      );
    } finally {
      await stranger.shutdown();
      stranger.dispose();
    }
  });


  test('değişen bir şey yoksa envanter boşuna gidip gelmez', () async {
    await joinAccepted();
    ayseInv.add('Kutu');
    await eventually(() => aliInv.named('Kutu') != null);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    // Damgalar oturduktan sonra konuşacak bir şey kalmamalı.
    await ayse.syncNow();
    final quiet = ayseInv.snapshots;
    await ayse.syncNow();
    await ayse.syncNow();
    expect(ayseInv.snapshots, quiet, reason: 'durum bir daha gönderilmedi');

    // Yeni bir kayıt yine konuşturur.
    ayseInv.add('Raf');
    await ayse.syncNow();
    expect(ayseInv.snapshots, greaterThan(quiet));
    await eventually(() => aliInv.named('Raf') != null);
  });

  /// Envanter değişirken eski envanterin servisi kapanır, hemen ardından veritabanı
  /// değişir. Kapanış döndükten sonra yazılan her şey yeni envantere giderdi.
  group('kapanış süren alışverişi yarım bırakmaz', () {
    Future<void> settled() async {
      await joinAccepted();
      await eventually(() => ayse.config.lastSyncAt != null && !ayse.syncing && !ali.syncing);
    }

    test('yanıt bekleyen alışveriş kesilir; döndükten sonra ayarlar yazılmaz', () async {
      await settled();
      // Ali gelen durumu geç işler: Ayşe'nin gönderimi o süre boyunca yanıt bekler.
      aliInv.mergeDelay = const Duration(milliseconds: 1200);
      ayseInv.add('Raf');
      final exchange = ayse.syncNow();
      await eventually(() => aliInv.merging > 0);
      final store = ayse.configStore as MemorySharingConfigStore;
      final saved = store.value!.lastSyncAt;

      await ayse.shutdown();
      expect(aliInv.merging, greaterThan(0), reason: 'kapanış karşının yanıtını beklemez, bağlantıyı keser');
      await exchange; // kesilen alışveriş hata fırlatmadan biter
      await eventually(() => aliInv.merging == 0);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(store.value!.lastSyncAt, saved, reason: 'kapandıktan sonra ayar yazılmaz');
    });

    test('işlenmekte olan birleştirme bitmeden kapanış dönmez; sonrasında yenisi başlamaz', () async {
      await settled();
      // Ayşe gelen durumu yavaş birleştirir; iki tarafta da yeni kayıt var.
      ayseInv.mergeDelay = const Duration(milliseconds: 400);
      aliInv.add('Raf');
      ayseInv.add('Kutu');
      final exchange = ayse.syncNow();
      await eventually(() => ayseInv.merging > 0);

      await ayse.shutdown();
      expect(ayseInv.merging, 0, reason: 'süren birleştirme veritabanı kapanmadan bitmeli');
      expect(ayseInv.named('Raf'), isNotNull);
      await exchange;
      // Ali yeniden gönderse de kapanmış servis hiçbir şey birleştirmez.
      aliInv.add('Masa');
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(ayseInv.merging, 0);
      expect(ayseInv.named('Masa'), isNull);
    });
  });
}
