import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/services/label_sheet.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/ui/label_flows.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Yazdırılacak QR etiket sayfası.
void main() {
  pw.Font font(String file) =>
      pw.Font.ttf(ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync()));

  List<LabelEntry> entries(int n) => [
        for (var i = 0; i < n; i++)
          LabelEntry(
            payload: 'envanter://container/id-$i?n=Kutu%20$i',
            // Türkçe harfler ve sığmayacak kadar uzun bir ad da olsun.
            title: i == 0 ? 'Çok uzun adlı, iki satıra sığmayacak kadar uzun bir ağaç işleri kutusu' : 'Kutu $i ğüşiöç',
            caption: 'Ana ekran / Garaj / Üst raf',
            color: 0xFFE0C9A6,
          ),
      ];

  testWidgets("PDF'in yüklediği yazı tipleri uygulama paketinde bu adlarla duruyor", (tester) async {
    for (final file in ['Fraunces-SemiBold.ttf', 'Manrope-SemiBold.ttf']) {
      final data = await tester.runAsync(() => rootBundle.load('assets/fonts/$file'));
      expect(data!.lengthInBytes, greaterThan(10000), reason: file);
    }
  });

  test('sayfa sayısı etiket boyuna göre', () {
    expect(LabelSize.small.perPage, 24);
    expect(LabelSize.medium.perPage, 12);
    expect(LabelSize.large.perPage, 6);
    expect(LabelSize.small.pagesFor(0), 0);
    expect(LabelSize.small.pagesFor(24), 1);
    expect(LabelSize.small.pagesFor(25), 2);
    expect(LabelSize.large.pagesFor(13), 3);
  });

  test('uygulamanın yazı tipleriyle PDF üretilir; sayfa arttıkça dosya büyür', () async {
    final display = font('Fraunces-SemiBold.ttf');
    final body = font('Manrope-SemiBold.ttf');
    final one = await LabelSheet.build(entries(5), size: LabelSize.large, display: display, body: body);
    final three = await LabelSheet.build(entries(13), size: LabelSize.large, display: display, body: body);
    expect(String.fromCharCodes(one.take(5)), '%PDF-');
    expect(three.length, greaterThan(one.length));
    // Küçük etiketle aynı 13 kayıt tek sayfaya sığar.
    final small = await LabelSheet.build(entries(13), size: LabelSize.small, display: display, body: body);
    expect(String.fromCharCodes(small.take(5)), '%PDF-');
  });

  group('klasörden etiket', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppPaths.useDirectory(Directory.systemTemp.createTempSync('envanter_labels').path);
    });

    tearDown(() async => AppDatabase.instance.close());

    test('klasör ve alt klasörleri; istenirse eşyalar da, destedeki sırayla', () async {
      await AppDatabase.instance.openForTest(inMemory: true);
      final store = InventoryStore();
      await store.init();
      Future<Node> add(String parent, NodeKind kind, String name) async {
        final n = store.draft(parentId: parent, kind: kind).copyWith(name: name);
        await store.commit(n);
        return store.byId(n.id)!;
      }

      final garaj = await add(Roots.home, NodeKind.container, 'Garaj');
      final raf = await add(garaj.id, NodeKind.container, 'Raf');
      await add(raf.id, NodeKind.item, 'Pil');
      await add(garaj.id, NodeKind.item, 'Matkap');
      final eski = await add(garaj.id, NodeKind.container, 'Eski');
      await store.moveToTrash(eski.id);

      expect(LabelFlows.subtreeOf(store, garaj, items: false).map((n) => n.name), ['Garaj', 'Raf']);
      expect(
        LabelFlows.subtreeOf(store, garaj, items: true).map((n) => n.name),
        ['Garaj', 'Raf', 'Pil', 'Matkap'],
      );
    });
  });
}
