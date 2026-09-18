// Ölçüm: bir eşitleme turunda ana iş parçacığını meşgul eden adımların süresi,
// 2.000 ve 5.000 kayıtla. Adı _test ile bitmediği için test takımına girmez:
// `flutter test test/bench/sync_bench.dart` (sonuç "OLCUM" satırlarında). Hata ayıklama
// modunda ölçer; telefonun işlemcisi daha yavaş, derlenmiş kod daha hızlıdır: sayılar
// kabaca telefondakiyle aynı büyüklüktedir, asıl anlamlı olan önce/sonra oranıdır.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/wire.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// [run] sürerken olay döngüsünün en uzun kesintisiz meşguliyeti (ms): arayüzün
/// donmuş kalacağı süre. Kısa aralıklı bir sayaç ne kadar gecikti diye bakılır.
Future<(T, int)> stall<T>(Future<T> Function() run) async {
  var worst = 0;
  var last = DateTime.now().microsecondsSinceEpoch;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now - last > worst) worst = now - last;
    last = now;
  });
  await Future<void>.delayed(const Duration(milliseconds: 5));
  worst = 0;
  last = DateTime.now().microsecondsSinceEpoch;
  final result = await run();
  await Future<void>.delayed(const Duration(milliseconds: 5));
  timer.cancel();
  return (result, worst ~/ 1000);
}

int median(List<int> xs) => (xs..sort())[xs.length ~/ 2];

int timed(void Function() f, {int rounds = 5}) {
  final times = <int>[];
  for (var i = 0; i < rounds; i++) {
    final w = Stopwatch()..start();
    f();
    times.add(w.elapsedMicroseconds);
  }
  return median(times) ~/ 1000;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final count in [2000, 5000]) {
    test('eşitleme adımları: $count kayıt', () async {
      await AppDatabase.instance.openForTest(inMemory: true);
      final store = InventoryStore()..authorId = 'ayse';
      await store.init();
      await store.updateSettings(store.settings.copyWith(language: AppLanguage.turkish));
      // Gerçeğe yakın bir envanter: onda biri klasör, notlar, adetler, tarihler, birkaç ek.
      final folders = <String>[];
      final nodes = <Node>[];
      for (var i = 0; i < count; i++) {
        final folder = i % 10 == 0;
        final parent = folders.isEmpty || i % 97 == 0 ? Roots.home : folders[i % folders.length];
        var n = store.draft(parentId: parent, kind: folder ? NodeKind.container : NodeKind.item).copyWith(
              name: folder ? 'Klasör $i' : 'Eşya numara $i',
              note: i % 3 == 0 ? 'Bu kaydın bir iki satırlık notu var; nerede durduğu ve ne işe yaradığı yazıyor.' : null,
              quantity: !folder && i % 4 == 0 ? i % 9 : null,
              expiresAt: !folder && i % 7 == 0 ? DateTime(2027, 1 + i % 12, 1 + i % 27) : null,
              barcode: !folder && i % 5 == 0 ? '869${(1000000000 + i)}' : null,
              attachments: i % 25 == 0
                  ? [Attachment(id: 'a$i', name: 'Kılavuz', addedAt: DateTime(2026, 9, 1), url: 'https://ornek.com/k/$i')]
                  : const [],
            );
        if (folder) folders.add(n.id);
        nodes.add(n);
      }
      await store.importBackup(nodes: {for (final n in nodes) n.id: n}, tombstones: const {}, privateIds: const {});
      expect(store.totalRecordCount, count);

      // 1) Giden durum: anlık görüntü + metne çevirme + bayt + imza için özet.
      late List<int> body;
      final build = timed(() {
        final snap = store.snapshot();
        final state = SyncState(nodes: snap.nodes, tombstones: snap.tombstones, members: const [], from: 'ayse');
        body = utf8.encode(jsonEncode(state.toJson()));
      });
      final sign = timed(() => sha256.convert(body));
      // 2) Gelen durum: çözme + doğrulama (her kayıt sanitizeNode'dan geçer).
      late SyncState incoming;
      final parse = timed(() => incoming = SyncState.fromJson(jsonDecode(utf8.decode(body))));
      // 3) Damga (değişiklikten sonra bir kez).
      final stamp = timed(() => stateStampOf(incoming.nodes.values, incoming.tombstones));

      // 4) Birleştirme: karşıda tek bir kayıt değişmiş.
      final one = incoming.nodes.values.firstWhere((n) => !n.isContainer);
      final changed = {
        ...incoming.nodes,
        one.id: one.copyWith(
          name: 'Değişti',
          updatedAt: DateTime.now().add(const Duration(seconds: 5)),
          updatedBy: 'ali',
          fieldTimes: {...one.fieldTimes, 'name': DateTime.now().millisecondsSinceEpoch + 5000},
        ),
      };
      final watch = Stopwatch()..start();
      final (stats, merging) = await stall(() => store.mergeRemote(nodes: changed, tombstones: const {}, from: 'ali'));
      final mergeTotal = watch.elapsedMilliseconds;
      expect(stats.updated, 1);

      // 5) Aynısı, olay döngüsünün gözüyle: hazırlama ve çözme tek parça mı sürüyor?
      final (_, buildStall) = await stall(() async {
        final snap = store.snapshot();
        utf8.encode(jsonEncode(SyncState(nodes: snap.nodes, tombstones: snap.tombstones, members: const []).toJson()));
      });
      final (_, parseStall) = await stall(() async => SyncState.fromJson(jsonDecode(utf8.decode(body))));

      // 6) Uygulamanın kullandığı yol: büyük durum ayrı yalıtımda (bkz. wire.dart).
      final snap = store.snapshot();
      final state = SyncState(nodes: snap.nodes, tombstones: snap.tombstones, members: const [], from: 'ayse');
      stateOffloadCount = 0;
      final signer = RequestSigner(RequestSigner.newKey());
      final w1 = Stopwatch()..start();
      final (encoded, offBuild) = await stall(() => encodeState(state));
      final offBuildTotal = w1.elapsedMilliseconds;
      final now = DateTime.now();
      final headers = signer.headers('POST', '/state', encoded.body, now, digest: encoded.digest);
      final w2 = Stopwatch()..start();
      final ((ok, got), offParse) = await stall(() => verifyAndDecodeState(
            key: signer.key,
            method: 'POST',
            path: '/state',
            body: encoded.body,
            time: headers[RequestSigner.timeHeader],
            signature: headers[RequestSigner.signatureHeader],
            now: now,
          ));
      final offParseTotal = w2.elapsedMilliseconds;
      expect(ok, isTrue);
      expect(got!.nodes.length, count);
      expect(stateOffloadCount, 2, reason: 'ikisi de yalıtımda yapıldı');
      // ignore: avoid_print
      print('OLCUM $count yalıtımda: hazırla+özet kesintisiz $offBuild ms (toplam $offBuildTotal), '
          'doğrula+çöz kesintisiz $offParse ms (toplam $offParseTotal)');

      // ignore: avoid_print
      print('OLCUM $count kayıt, ${(body.length / 1024).round()} KB: '
          'hazırla $build ms (kesintisiz $buildStall), imza özeti $sign ms, '
          'çöz+doğrula $parse ms (kesintisiz $parseStall), damga $stamp ms, '
          'birleştir toplam $mergeTotal ms (kesintisiz $merging)');
      await AppDatabase.instance.close();
    });
  }
}
