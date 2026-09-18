import 'dart:io';

import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/core/theme.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/wire.dart';
import 'package:envanter/ui/lending_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppPaths.useDirectory(Directory.systemTemp.createTempSync('envanter_lending_test').path);
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('Emanet & Ödünç Veri Modeli', () {
    test('Node emanet alanları ve gecikme kontrolü', () {
      final now = DateTime.now();
      final item = Node(
        id: 'matkap',
        parentId: null,
        kind: NodeKind.item,
        name: 'Darbeli Matkap',
        color: 0,
        sortIndex: 0,
        createdAt: now,
        updatedAt: now,
        borrowedTo: 'Ahmet Yılmaz',
        borrowedAt: now.subtract(const Duration(days: 10)),
        returnDueAt: now.subtract(const Duration(days: 2)), // Gecikmiş
      );

      expect(item.isBorrowed, isTrue);
      expect(item.isBorrowOverdue, isTrue);
      expect(item.borrowedTo, 'Ahmet Yılmaz');

      // Vadesi gelmemiş
      final futureItem = item.copyWith(
        returnDueAt: now.add(const Duration(days: 5)),
      );
      expect(futureItem.isBorrowed, isTrue);
      expect(futureItem.isBorrowOverdue, isFalse);

      // İade edildiğinde alanların temizlenmesi
      final returnedItem = futureItem.copyWith(clearBorrow: true);
      expect(returnedItem.isBorrowed, isFalse);
      expect(returnedItem.borrowedTo, isNull);
      expect(returnedItem.borrowedAt, isNull);
      expect(returnedItem.returnDueAt, isNull);
    });

    test('Node cleanBorrower boşlukları ve gereksiz karakterleri temizler', () {
      expect(Node.cleanBorrower('  Mehmet Demir  '), 'Mehmet Demir');
      expect(Node.cleanBorrower('   '), isNull);
      expect(Node.cleanBorrower(null), isNull);
    });

    test('Veritabanı saklama ve okuma (şema 21)', () async {
      await AppDatabase.instance.openForTest(inMemory: true);
      final db = AppDatabase.instance.db;

      final now = DateTime(2026, 10, 15, 10, 0);
      final returnDate = DateTime(2026, 10, 25);
      final node = Node(
        id: 'testere',
        parentId: null,
        kind: NodeKind.item,
        name: 'Daire Testere',
        color: 0,
        sortIndex: 0,
        createdAt: now,
        updatedAt: now,
        borrowedTo: 'Canan',
        borrowedAt: now,
        returnDueAt: returnDate,
      );

      await db.insert('nodes', node.toMap());

      final rows = await db.query('nodes', where: 'id = ?', whereArgs: ['testere']);
      expect(rows, hasLength(1));
      final loaded = Node.fromMap(rows.first);

      expect(loaded.id, 'testere');
      expect(loaded.borrowedTo, 'Canan');
      expect(loaded.borrowedAt, now);
      expect(loaded.returnDueAt, returnDate);
      expect(loaded.isBorrowed, isTrue);
    });

    test('Eşitleme alanı ve wire sanitization (v23)', () {
      final now = DateTime(2026, 10, 17, 12, 0);
      final node = Node(
        id: 'lazer',
        parentId: null,
        kind: NodeKind.item,
        name: 'Lazer Metre',
        color: 0,
        sortIndex: 0,
        createdAt: now,
        updatedAt: now,
        borrowedTo: '  Ali Veli  ',
        borrowedAt: now,
        returnDueAt: now.add(const Duration(days: 7)),
      );
      final raw = node.toMap();

      final clean = sanitizeNode(raw);
      expect(clean, isNotNull);
      expect(clean?.borrowedTo, 'Ali Veli');
      expect(clean?.borrowedAt, isNotNull);
      expect(clean?.returnDueAt, isNotNull);
      // Emanet alanları 23'ten beri var; sonraki sürümler (24: fiyat, seri no) de taşır.
      expect(kDataVersion, greaterThanOrEqualTo(23));
    });
  });

  group('LendingPage ve UI Entegrasyonu', () {
    testWidgets('LendingPage aktif ve gecikmiş ödünçleri gösterir, iade alınabilir', (tester) async {
      late InventoryStore store;
      await tester.runAsync(() async {
        await AppDatabase.instance.openForTest(inMemory: true);
        store = InventoryStore();
        await store.init();
        await store.updateSettings(store.settings.copyWith(language: AppLanguage.turkish));

        final now = DateTime.now();
        final overdueItem = Node(
          id: 'item-1',
          parentId: null,
          kind: NodeKind.item,
          name: 'Hilti Kırıcı',
          color: 0,
          sortIndex: 0,
          createdAt: now,
          updatedAt: now,
          borrowedTo: 'Murat',
          borrowedAt: now.subtract(const Duration(days: 15)),
          returnDueAt: now.subtract(const Duration(days: 3)),
        );
        final activeItem = Node(
          id: 'item-2',
          parentId: null,
          kind: NodeKind.item,
          name: 'Kaynak Makinesi',
          color: 0,
          sortIndex: 1,
          createdAt: now,
          updatedAt: now,
          borrowedTo: 'Hasan',
          borrowedAt: now.subtract(const Duration(days: 2)),
          returnDueAt: now.add(const Duration(days: 5)),
        );

        await store.commit(overdueItem);
        await store.commit(activeItem);
      });

      expect(store.borrowedItems, hasLength(2));
      expect(store.overdueBorrowedItems, hasLength(1));
      expect(store.hasOverdueBorrow, isTrue);
      expect(store.knownBorrowers, containsAll(['Murat', 'Hasan']));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: InventoryScope(
            store: store,
            child: const LendingPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Başlık ve öğelerin listede olduğunu doğrula
      expect(find.text(store.strings.borrowedPageTitle), findsOneWidget);
      expect(find.text('Hilti Kırıcı'), findsOneWidget);
      expect(find.text('Kaynak Makinesi'), findsOneWidget);
      expect(find.textContaining('Murat'), findsWidgets);
      expect(find.textContaining('Hasan'), findsWidgets);

      // İade et butonu ile birini iade al
      final returnButtons = find.byTooltip(store.strings.markReturned);
      expect(returnButtons, findsNWidgets(2));
      await tester.runAsync(() async {
        await tester.tap(returnButtons.first);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(store.borrowedItems, hasLength(1));
    });
  });
}
