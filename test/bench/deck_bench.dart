// Ölçüm: deste kaydırılırken bir karenin (kurma + yerleşim + çizim kaydı)
// süresi, üç görünümde, 300 kayıtla. Adı _test ile bitmediği için test takımına girmez:
// `flutter test test/bench/deck_bench.dart` (sonuç "OLCUM" satırlarında). Hata ayıklama
// modunda ölçer: sayılar gerçek telefondakinden büyüktür, önce/sonra oranı anlamlıdır.
import 'dart:io';

import 'package:envanter/app.dart';
import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/data/settings.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/sharing_config.dart';
import 'package:envanter/sync/sharing_service.dart';
import 'package:envanter/ui/node_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  for (final view in DeckView.values) {
    testWidgets('kaydırma: ${view.name}', (tester) async {
      tester.view.physicalSize = const Size(411, 860) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      late InventoryStore store;
      late SharingService sharing;
      await tester.runAsync(() async {
        final dir = Directory.systemTemp.createTempSync('envanter_bench');
        AppPaths.useDirectory(dir.path);
        await AppDatabase.instance.openForTest();
        store = InventoryStore()..authorId = 'ayse';
        await store.init();
        await store.updateSettings(
          store.settings.copyWith(language: AppLanguage.turkish, userName: 'Ayşe', tipsSeen: true, deckView: view),
        );
        for (var i = 0; i < 30; i++) {
          await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Klasör $i'));
        }
        for (var i = 0; i < 270; i++) {
          await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
                name: 'Eşya $i',
                note: i.isEven ? 'Bir iki satırlık not; kartın çizgilerine oturur.' : '',
                quantity: i % 3 == 0 ? i % 7 : null,
              ));
        }
        sharing = SharingService(target: store, configStore: MemorySharingConfigStore(), displayName: () => 'Ayşe');
        await sharing.load();
      });
      await tester.pumpWidget(EnvanterApp(store: store, sharing: sharing));
      await tester.pumpAndSettle();

      final position = tester
          .state<ScrollableState>(
            find.descendant(of: find.byType(NodeListView), matching: find.byType(Scrollable)).first,
          )
          .position;
      final step = view == DeckView.deck ? 9.0 : 13.0;
      var offset = 0.0;
      // Isınma.
      for (var i = 0; i < 60; i++) {
        position.jumpTo(offset += step);
        await tester.pump();
      }
      final times = <int>[];
      for (var round = 0; round < 3; round++) {
        final watch = Stopwatch()..start();
        const frames = 240;
        for (var i = 0; i < frames; i++) {
          offset += step;
          if (offset > position.maxScrollExtent - 50) offset = 100;
          position.jumpTo(offset);
          await tester.pump();
        }
        times.add(watch.elapsedMicroseconds ~/ frames);
      }
      times.sort();
      // ignore: avoid_print
      print('OLCUM ${view.name}: kare başına ${times[1]} µs (en iyi ${times.first}, en kötü ${times.last})');
    });
  }
}
