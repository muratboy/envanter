// Emülatördeki uygulamayla ortak kullanımı denemek için bilgisayarda çalışan
// ikinci "telefon". Testlerle aynı eşitleme kodunu kullanır.
//
//   adb emu redir add udp:47810:47810      # duyurular emülatöre gitsin
//   SIM_MODE=owner  flutter test tool/lan_peer_sim.dart   # Ayşe sahibi, istekleri kabul eder
//   SIM_MODE=joiner SIM_TARGET=http://127.0.0.1:PORT flutter test tool/lan_peer_sim.dart
//                                                           # Veli, uygulamanın envanterine katılır
//   SIM_SCRIPT=1 (owner ile)  biri katıldıktan sonra Ayşe değişiklik yapar: bir
//                             eşyanın adını değiştirir, yeni eşya ekler, sonra
//                             bir eşyayı kayıp bildirir (uygulamadaki onay akışı için)
//   SIM_SCRIPT_AFTER=90       ilk değişiklik katılmadan bu kadar saniye sonra (varsayılan 20)
//   SIM_PURGE=1 (SIM_SCRIPT ile) senaryo yerine Ayşe "Blender"i kalıcı siler: yöneticiden
//                             gelse de uygulamada onaya düşer (kapalı envanterdeki "onay
//                             bekliyor" işaretini denemek için)
//   SIM_OLD=1 (joiner ile)    katıldıktan sonra eski bir uygulama gibi (veri
//                             sürümü göndermeden) durum ister: uygulama vermemeli,
//                             "Veli'nin uygulaması eski" demeli
//   SIM_HELD="Ad" (joiner ile)  katıldıktan ~20 sn sonra Veli bu adlı ortak eşyayı
//                             kendi "yalnızca bende" alanına alır: uygulamaya son
//                             sürümü gider (çekmecede, "Veli'de")
//   SIM_FIELD="Ad" (joiner ile) katıldıktan ~20 sn sonra Veli bu adlı eşyanın adını
//                             değiştirir ve 20 sn eşitlemeden bekler: o arada uygulamada
//                             aynı eşyanın adedi değiştirilirse ikisi de kalmalı (alan
//                             bazında birleştirme); uygulamanın onay listesinde yalnızca ad
//   SIM_AHEAD=10              bu "telefonun" saati 10 dakika ileri (imzalar da): saatleri
//                             farklı iki telefonun eşitlenmesini denemek için
//   SIM_CONFIG=build/sim_veli.json  kimlik ve anahtar dosyada durur, sonraki
//                             çalıştırma aynı üye olarak döner (uygulamada her denemede
//                             yeni bir "Veli" birikmesin; üye çıkarma yok)
import 'dart:convert';
import 'dart:io';

import 'package:envanter/data/node.dart';
import 'package:envanter/sync/discovery.dart';
import 'package:envanter/sync/sharing_config.dart';
import 'package:envanter/sync/sharing_service.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/fake_inventory.dart';

void log(String message) {
  final t = DateTime.now().toIso8601String().substring(11, 19);
  stdout.writeln('[$t] $message');
}

String names(FakeInventory inv) =>
    (inv.nodes.values.where((n) => !n.isDeleted).map((n) => n.name).toList()..sort()).join(', ');

class FileSharingConfigStore implements SharingConfigStore {
  FileSharingConfigStore(this.file);

  final File file;

  @override
  Future<SharingConfig?> load() async =>
      file.existsSync() ? SharingConfig.fromJson(jsonDecode(file.readAsStringSync())) : null;

  @override
  Future<void> save(SharingConfig config) async => file.writeAsStringSync(jsonEncode(config.toJson()));
}

void main() {
  test('ikinci telefon', () async {
    final mode = Platform.environment['SIM_MODE'] ?? 'owner';
    final inv = FakeInventory();
    final photo = File('test/fixtures/visual/stored_kutu.jpg');

    if (mode == 'owner') {
      final mutfak = inv.add('Mutfak', kind: NodeKind.container);
      final tencere = inv.add('Tencere seti', parent: mutfak.id, image: 'images/sim-tencere.jpg');
      if (photo.existsSync()) inv.files[tencere.imagePath!] = photo.readAsBytesSync();
      inv.add('Blender', parent: mutfak.id);
    } else if (Platform.environment['SIM_OLD'] != '1' && Platform.environment['SIM_FIELD'] == null) {
      // Eski uygulama ve alan denemesinde uygulamaya kayıt taşınmasın.
      inv.add('Velinin matkabı');
    }

    final name = mode == 'owner' ? 'Ayşe' : 'Veli';
    final service = SharingService(
      target: inv,
      configStore: switch (Platform.environment['SIM_CONFIG']) {
        final String path => FileSharingConfigStore(File(path)),
        null => MemorySharingConfigStore(),
      },
      displayName: () => name,
      discovery: LanDiscovery(
        port: 47811,
        targets: [(InternetAddress.loopbackIPv4, 47810)],
        interval: const Duration(seconds: 1),
        expiry: const Duration(seconds: 6),
      ),
      periodic: const Duration(seconds: 8),
      resyncAfter: const Duration(seconds: 5),
      clock: () => DateTime.now().add(Duration(minutes: int.parse(Platform.environment['SIM_AHEAD'] ?? '0'))),
    );
    await service.load();
    // Simülatör gelen değişiklikleri sormadan alır; onay akışı uygulamada sınanıyor.
    await service.setAutoAccept(true);
    if (mode == 'owner') await service.rename('Ev');
    await service.setEnabled(true);
    log('$name hazır ($mode). Envanter: ${names(inv)}');

    var lastNames = names(inv);
    var wasAdmin = service.config.isAdmin;
    service.addListener(() {
      if (service.config.isAdmin != wasAdmin) {
        wasAdmin = service.config.isAdmin;
        log('ROL: $name artık ${wasAdmin ? 'ana kullanıcı' : 'üye'}');
      }
      for (final p in service.pendingJoins) {
        log('KATILMA İSTEĞİ: "${p.request.name}" → kabul ediliyor');
        service.decideJoin(p, true);
      }
      final now = names(inv);
      if (now != lastNames) {
        lastNames = now;
        log('ENVANTER DEĞİŞTİ: $now | fotoğraflar: ${inv.files.keys.join(', ')}');
      }
    });

    if (mode == 'joiner') {
      final target = Uri.parse(Platform.environment['SIM_TARGET']!);
      final peer = DiscoveredPeer(
        info: Announcement(
          deviceId: 'uygulama',
          deviceName: '',
          inventoryId: '-',
          inventoryName: '',
          joinable: true,
          httpPort: target.port,
          dataVersion: kDataVersion,
        ),
        address: InternetAddress(target.host),
        lastSeen: DateTime.now(),
      );
      log('Uygulamaya katılma isteği gönderiliyor: $target');
      final outcome = await service.requestJoin(peer);
      log('SONUÇ: $outcome | envanter: ${names(inv)}');
      if (outcome == JoinOutcome.accepted) {
        final held = Platform.environment['SIM_HELD'];
        final field = Platform.environment['SIM_FIELD'];
        if (Platform.environment['SIM_OLD'] == '1') {
          // Eski uygulama: sürüm başlığı yok, yalnızca imza ve kimlik.
          final http = HttpClient();
          final req = await http.getUrl(target.replace(path: '/state'));
          RequestSigner(service.config.key).headers('GET', '/state', const [], DateTime.now()).forEach(req.headers.set);
          req.headers.set(kFromHeader, service.config.deviceId);
          final res = await req.close();
          final body = await res.transform(const Utf8Decoder()).join();
          http.close(force: true);
          log('ESKİ UYGULAMA GİBİ /state: HTTP ${res.statusCode} ${body.length > 80 ? body.substring(0, 80) : body}');
          await service.shutdown();
          return;
        }
        // Emülatör bu cihazı bulamaz (NAT); eşitlemeyi buradan sürdürelim.
        for (var i = 0; i < 12; i++) {
          await Future<void>.delayed(const Duration(seconds: 10));
          if (held != null && i == 1) {
            final n = inv.named(held);
            if (n == null) {
              log('SENARYO: "$held" bulunamadı');
            } else {
              // Uygulamadaki InventoryStore'un özel alana alınan ortak kayıt için
              // gönderdiği son sürümün aynısı.
              inv.update(
                n.id,
                (n) => n.copyWith(clearParent: true, inDrawer: true, clearLost: true, heldBy: service.config.deviceId),
                by: service.config.deviceId,
              );
              log('SENARYO: Veli "$held" eşyasını kendi özel alanına aldı');
            }
          }
          if (field != null && i == 1) {
            final n = inv.named(field);
            if (n == null) {
              log('SENARYO: "$field" bulunamadı');
            } else {
              inv.update(n.id, (n) => n.copyWith(name: '${n.name} (Veli)'), by: service.config.deviceId);
              log('SENARYO: Veli "$field" adını değiştirdi (adet ${n.quantity}); 20 sn eşitlemiyor, '
                  'şimdi uygulamada adedini değiştir');
              await Future<void>.delayed(const Duration(seconds: 20));
            }
          }
          final fresh = DiscoveredPeer(
            info: Announcement(
              deviceId: 'uygulama',
              deviceName: '',
              inventoryId: service.config.inventoryId,
              inventoryName: '',
              joinable: true,
              httpPort: target.port,
              dataVersion: kDataVersion,
            ),
            address: InternetAddress(target.host),
            lastSeen: DateTime.now(),
          );
          // Üye olduğu için hemen kabul + eşitleme. Uygulama arka plandan dönünce
          // sunucusu yeni bir porta açılır; o zaman adb forward yenilenmeli.
          final outcome = await service.requestJoin(fresh);
          if (outcome != JoinOutcome.accepted) {
            log('EŞİTLENEMEDİ ($outcome): uygulama açık mı, port değişti mi?');
            continue;
          }
          log('eşitlendi | envanter: ${names(inv)}');
          if (field != null) {
            final n = inv.nodes.values.where((n) => n.name.startsWith(field)).firstOrNull;
            if (n != null) log('  "${n.name}": adet ${n.quantity}');
          }
        }
      }
    } else {
      final script = Platform.environment['SIM_SCRIPT'] == '1';
      // İlk değişikliğin katılmadan kaç saniye sonra yapılacağı (kapalı envanterin
      // arka plan eşitlemesini denerken uygulamaya envanteri kapatma zamanı bırakmak için).
      final after = int.parse(Platform.environment['SIM_SCRIPT_AFTER'] ?? '20');
      var step = 0;
      DateTime? joinedAt;
      // Karşı taraf bize veri ittiğinde servis bildirim göndermiyor; envanteri
      // düzenli aralıklarla kendimiz yoklayalım.
      final end = DateTime.now().add(Duration(seconds: int.parse(Platform.environment['SIM_SECONDS'] ?? '240')));
      while (DateTime.now().isBefore(end)) {
        if (script && service.config.isShared) {
          joinedAt ??= DateTime.now();
          final since = DateTime.now().difference(joinedAt).inSeconds;
          final me = service.config.deviceId;
          if (step == 0 && since >= after && Platform.environment['SIM_PURGE'] == '1') {
            step = 2;
            inv.purge(inv.named('Blender')!.id);
            log('SENARYO: Blender kalıcı silindi');
          } else if (step == 0 && since >= after) {
            step++;
            final blender = inv.named('Blender')!;
            inv.update(blender.id, (n) => n.copyWith(name: 'Blender (bozuk)'), by: me);
            final mutfak = inv.named('Mutfak')!;
            final kahve = inv.add('Kahve makinesi', parent: mutfak.id);
            inv.update(kahve.id, (n) => n, by: me);
            log('SENARYO: Blender adı değişti, Kahve makinesi eklendi');
          } else if (step == 1 && since >= after + 25) {
            step++;
            final tencere = inv.named('Tencere seti')!;
            inv.update(
              tencere.id,
              (n) => n.copyWith(clearParent: true, lostAt: DateTime.now(), lostFrom: n.parentId),
              by: me,
            );
            log('SENARYO: Tencere seti kayıp bildirildi');
          }
        }
        await Future<void>.delayed(const Duration(seconds: 3));
        final now = names(inv);
        if (now != lastNames) {
          lastNames = now;
          log('ENVANTER DEĞİŞTİ: $now | fotoğraflar: ${inv.files.keys.join(', ')}');
        }
      }
    }
    await service.shutdown();
  }, timeout: const Timeout(Duration(minutes: 30)));
}
