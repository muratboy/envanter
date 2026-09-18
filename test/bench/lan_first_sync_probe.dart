// Yoklama (test turunun parçası değil): iki cihazın loopback'te buluşup katılması ve ilk
// eşitlemesi art arda çalıştırılır, düşen turda iki tarafın durumu yazılır. Seyrek düşen
// LAN testinin nedeni bununla bulundu (bkz. test/support/ports.dart). Yük altında denemek
// için aynı anda birkaç süreç çalıştır:
//   PROBE_ROUNDS=400 flutter test test/bench/lan_first_sync_probe.dart
//   PROBE_OLD=1 ...   eski, rastgele kapı seçimiyle (karşılaştırma için)
import 'dart:io';
import 'dart:math';

import 'package:envanter/sync/discovery.dart';
import 'package:envanter/sync/sharing_config.dart';
import 'package:envanter/sync/sharing_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_inventory.dart';
import '../support/ports.dart';

Future<bool> soon(bool Function() condition, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return true;
}

void main() {
  test('yoklama', () async {
    final rounds = int.parse(Platform.environment['PROBE_ROUNDS'] ?? '100');
    var failed = 0;
    for (var i = 0; i < rounds; i++) {
      final lease = Platform.environment['PROBE_OLD'] == '1' ? null : await leasePorts();
      final base = lease?.base ?? 41000 + Random().nextInt(20000);
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
      final ayse = device('Ayşe', FakeInventory(), base, base + 1);
      final ali = device('Ali', FakeInventory(), base + 1, base);
      await ayse.load();
      await ali.load();
      await ayse.setAutoAccept(true);
      await ali.setAutoAccept(true);
      final started = DateTime.now();
      String stage = 'açılış';
      var ok = true;
      try {
        await ayse.setEnabled(true);
        await ali.setEnabled(true);
        stage = 'keşif';
        ok = await soon(() => ali.joinableInventories.isNotEmpty);
        if (ok) {
          final request = ali.requestJoin(ali.joinableInventories.single);
          stage = 'istek';
          ok = await soon(() => ayse.pendingJoins.isNotEmpty);
          if (ok) {
            ayse.decideJoin(ayse.pendingJoins.single, true);
            final outcome = await request;
            stage = 'kabul ($outcome)';
            ok = outcome == JoinOutcome.accepted;
          }
        }
        if (ok) {
          stage = 'ali→ayşe';
          ok = await soon(() => ali.config.syncedWith.containsKey(ayse.config.deviceId));
        }
        if (ok) {
          stage = 'ayşe→ali';
          ok = await soon(() => ayse.config.syncedWith.containsKey(ali.config.deviceId));
        }
      } catch (e) {
        ok = false;
        stage = '$stage: $e';
      }
      if (!ok) {
        failed++;
        // ignore: avoid_print
        print('DÜŞTÜ tur $i kapı $base aşama "$stage" süre ${DateTime.now().difference(started).inMilliseconds} ms\n'
            '  ali: hata=${ali.lastError} çalışıyor=${ali.running} üyeler=${ali.config.members.map((m) => m.name).toList()} '
            'çevrimiçi=${ali.onlineMembers.map((p) => p.info.deviceName).toList()} '
            'görülen=${ali.joinableInventories.length} eşit=${ali.config.syncedWith.length} '
            'env=${ali.config.inventoryId == ayse.config.inventoryId}\n'
            '  ayşe: hata=${ayse.lastError} çalışıyor=${ayse.running} üyeler=${ayse.config.members.map((m) => m.name).toList()} '
            'çevrimiçi=${ayse.onlineMembers.map((p) => p.info.deviceName).toList()} eşit=${ayse.config.syncedWith.length}');
      }
      await ayse.shutdown();
      await ali.shutdown();
      ayse.dispose();
      ali.dispose();
      lease?.release();
    }
    // ignore: avoid_print
    print('YOKLAMA BİTTİ: $rounds turda $failed düşme');
  }, timeout: const Timeout(Duration(minutes: 30)));
}
