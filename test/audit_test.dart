import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/core/theme.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/ui/audit_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppPaths.useDirectory(Directory.systemTemp.createTempSync('envanter_audit_test').path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('Klasör Barkodu ve Veri Uyumluluğu', () {
    test('Klasör (container) kaydı barkod taşıyabilir ve veritabanına yazılıp okunur', () async {
      await AppDatabase.instance.openForTest(inMemory: true);
      final db = AppDatabase.instance.db;

      final now = DateTime(2026, 10, 19, 10, 0);
      final container = Node(
        id: 'box-101',
        parentId: null,
        kind: NodeKind.container,
        name: 'Elektronik Kolisi',
        color: 0,
        sortIndex: 0,
        createdAt: now,
        updatedAt: now,
        barcode: 'BOX-ELK-101',
      );

      await db.insert('nodes', container.toMap());

      final rows = await db.query('nodes', where: 'id = ?', whereArgs: ['box-101']);
      expect(rows, hasLength(1));
      final loaded = Node.fromMap(rows.first);

      expect(loaded.id, 'box-101');
      expect(loaded.isContainer, isTrue);
      expect(loaded.barcode, 'BOX-ELK-101');
    });
  });

  group('AuditItemRecord Durum Geçişleri', () {
    test('Kayıt doğrulama ve adet sapma durumları', () {
      final now = DateTime.now();
      final item = Node(
        id: 'item-1',
        parentId: 'box-1',
        kind: NodeKind.item,
        name: 'Vida Paketi',
        color: 0,
        sortIndex: 0,
        createdAt: now,
        updatedAt: now,
        quantity: 10,
      );

      final record = AuditItemRecord(
        node: item,
        expectedQuantity: 10,
        countedQuantity: 0,
        status: AuditStatus.uncounted,
      );

      expect(record.isCounted, isFalse);
      expect(record.hasDiscrepancy, isFalse);

      // Doğrulandı
      record.countedQuantity = 10;
      record.status = AuditStatus.verified;
      expect(record.isCounted, isTrue);
      expect(record.hasDiscrepancy, isFalse);

      // Sapma (discrepancy)
      record.countedQuantity = 7;
      record.status = AuditStatus.discrepancy;
      expect(record.isCounted, isTrue);
      expect(record.hasDiscrepancy, isTrue);

      // Eksik (missing)
      record.countedQuantity = 0;
      record.status = AuditStatus.missing;
      expect(record.isCounted, isTrue);
      expect(record.hasDiscrepancy, isTrue);
    });
  });

  group('Hızlı Sayım ve Mutabakat Entegrasyonu', () {
    testWidgets('Sayım ekranı eşyaları listeler, hızlı doğrulama ve sayım yapılabilir', (tester) async {
      late InventoryStore store;
      await tester.runAsync(() async {
        await AppDatabase.instance.openForTest(inMemory: true);
        store = InventoryStore();
        await store.init();
        await store.updateSettings(store.settings.copyWith(language: AppLanguage.turkish));

        final now = DateTime.now();
        final box = Node(
          id: 'box-a',
          parentId: null,
          kind: NodeKind.container,
          name: 'Takım Çantası',
          color: 0,
          sortIndex: 0,
          createdAt: now,
          updatedAt: now,
          barcode: 'TC-001',
        );
        final item1 = Node(
          id: 'item-a1',
          parentId: 'box-a',
          kind: NodeKind.item,
          name: 'Pense',
          color: 0,
          sortIndex: 0,
          createdAt: now,
          updatedAt: now,
          quantity: 2,
          barcode: 'BAR-PENSE',
        );
        final item2 = Node(
          id: 'item-a2',
          parentId: 'box-a',
          kind: NodeKind.item,
          name: 'Tornavida',
          color: 0,
          sortIndex: 1,
          createdAt: now,
          updatedAt: now,
          quantity: 1,
        );

        await store.commit(box);
        await store.commit(item1);
        await store.commit(item2);
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: InventoryScope(
            store: store,
            child: const AuditPage(
              containerId: 'box-a',
              containerName: 'Takım Çantası',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // İki eşya da listede görünmeli
      expect(find.text('Pense'), findsOneWidget);
      expect(find.text('Tornavida'), findsOneWidget);

      // Pense için tek tıkla doğrula butonuna bas
      final verifyButtons = find.text(store.strings.verifyAction);
      expect(verifyButtons, findsAtLeastNWidgets(1));
      await tester.tap(verifyButtons.first);
      await tester.pumpAndSettle();

      // Tornavida için eksik işaretle: more_vert_rounded menüsünden
      final moreButtons = find.byIcon(Icons.more_vert_rounded);
      expect(moreButtons, findsAtLeastNWidgets(1));
      await tester.tap(moreButtons.last);
      await tester.pumpAndSettle();

      final markMissingItem = find.text(store.strings.markMissingAction);
      expect(markMissingItem, findsOneWidget);
      await tester.tap(markMissingItem);
      await tester.pumpAndSettle();

      // Tamamla butonuna tıkla ve mutabakat alt sayfasını aç
      final finishButton = find.byTooltip(store.strings.finishAudit);
      expect(finishButton, findsOneWidget);
      await tester.tap(finishButton);
      await tester.pumpAndSettle();

      // Mutabakat özetinde başlık görünmeli
      expect(find.text(store.strings.auditSummaryTitle), findsOneWidget);
    });

    test('Mutabakat eylemleri veritabanına doğru uygulanır', () async {
      await AppDatabase.instance.openForTest(inMemory: true);
      final store = InventoryStore();
      await store.init();

      final now = DateTime.now();
      final box = Node(
        id: 'box-b',
        parentId: null,
        kind: NodeKind.container,
        name: 'Depo Kutusu',
        color: 0,
        sortIndex: 0,
        createdAt: now,
        updatedAt: now,
      );
      final itemDiscrepancy = Node(
        id: 'item-b1',
        parentId: 'box-b',
        kind: NodeKind.item,
        name: 'Cıvata',
        color: 0,
        sortIndex: 0,
        createdAt: now,
        updatedAt: now,
        quantity: 50,
      );
      final itemMissing = Node(
        id: 'item-b2',
        parentId: 'box-b',
        kind: NodeKind.item,
        name: 'Somun',
        color: 0,
        sortIndex: 1,
        createdAt: now,
        updatedAt: now,
        quantity: 20,
      );
      final itemOtherFolder = Node(
        id: 'item-other',
        parentId: null, // Ana ekranda duruyordu
        kind: NodeKind.item,
        name: 'Pul',
        color: 0,
        sortIndex: 2,
        createdAt: now,
        updatedAt: now,
        quantity: 5,
      );

      await store.commit(box);
      await store.commit(itemDiscrepancy);
      await store.commit(itemMissing);
      await store.commit(itemOtherFolder);

      // 1. Adet güncellemesi: Cıvata 50 -> 42
      await store.commit(itemDiscrepancy.copyWith(quantity: 42));
      expect(store.byId('item-b1')?.quantity, 42);

      // 2. Eksik olan eşyayı kayıp olarak işaretle
      await store.markLost(itemMissing.id);
      expect(store.byId('item-b2')?.isLost, isTrue);

      // 3. Başka yerde olan eşyayı bu kutunun içine taşı
      await store.move(itemOtherFolder.id, 'box-b');
      expect(store.byId('item-other')?.parentId, 'box-b');
    });
  });
}
