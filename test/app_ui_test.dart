import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:envanter/app.dart';
import 'package:envanter/core/app_paths.dart';
import 'package:envanter/core/strings.dart';
import 'package:envanter/core/theme.dart';
import 'package:envanter/core/time_span.dart';
import 'package:envanter/data/database.dart';
import 'package:envanter/data/lots.dart';
import 'package:envanter/data/node.dart';
import 'package:envanter/data/settings.dart';
import 'package:envanter/services/image_service.dart';
import 'package:envanter/services/qr_service.dart';
import 'package:envanter/state/inventory_store.dart';
import 'package:envanter/sync/sharing_config.dart';
import 'package:envanter/sync/sharing_service.dart';
import 'package:envanter/ui/actions.dart';
import 'package:envanter/ui/audit_page.dart';
import 'package:envanter/ui/burst_add_page.dart';
import 'package:envanter/ui/container_screen.dart';
import 'package:envanter/ui/dates_page.dart';
import 'package:envanter/ui/editor_page.dart';
import 'package:envanter/ui/home_screen.dart';
import 'package:envanter/ui/lending_page.dart';
import 'package:envanter/ui/node_list_view.dart';
import 'package:envanter/ui/search_page.dart';
import 'package:envanter/ui/settings_page.dart';
import 'package:envanter/ui/shell.dart';
import 'package:envanter/ui/shopping_page.dart';
import 'package:envanter/ui/visual_search_page.dart';
import 'package:envanter/ui/trash_page.dart';
import 'package:envanter/ui/widgets/entrance.dart';
import 'package:envanter/ui/widgets/left_drawer.dart';
import 'package:envanter/ui/widgets/node_card.dart';
import 'package:envanter/ui/widgets/paper.dart';
import 'package:envanter/ui/widgets/photo_viewer.dart';
import 'package:envanter/ui/widgets/today_strip.dart';
import 'package:envanter/ui/widgets/unsorted_drawer.dart';
import 'package:envanter/ui/widgets/stacked_card_list.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Uygulamanın tamamı, gerçek mağaza ve bellek içi veritabanıyla.
void main() {
  late InventoryStore store;
  late SharingService sharing;
  const s = TrStrings();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Veritabanı gerçek zamanda çalışıyor; testin sahte saatinde beklenemez.
  Future<void> settleIo(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Future<void> boot(WidgetTester tester, {Size size = const Size(411, 860)}) async {
    tester.view.physicalSize = size * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('envanter_ui');
      AppPaths.useDirectory(dir.path);
      await AppDatabase.instance.openForTest();
      store = InventoryStore()..authorId = 'ayse';
      await store.init();
      await store.updateSettings(
        store.settings.copyWith(language: AppLanguage.turkish, userName: 'Ayşe', tipsSeen: true),
      );
      sharing = SharingService(
        target: store,
        configStore: MemorySharingConfigStore(),
        displayName: () => 'Ayşe',
      );
      await sharing.load();
    });
    await tester.pumpWidget(EnvanterApp(store: store, sharing: sharing));
    await tester.pumpAndSettle();
  }

  /// Fotoğraflı eşya (1x1 PNG: gerçek, çözülebilen bir görüntü). runAsync içinde çağrılır.
  Future<void> addPhotoItem(String name) async {
    const png = [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
      0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, //
      0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, //
      0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    final rel = 'images/$name.png';
    File(AppPaths.abs(rel))
      ..createSync(recursive: true)
      ..writeAsBytesSync(png);
    AppPaths.forget(rel);
    await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name, imagePath: rel));
  }

  /// Alttaki görünüm düğmesiyle istenen görünüme geçer (Deste / Liste / Izgara).
  /// Düğme sırayla dolaşır: gerekirse iki kez dokunulur. Son dokunuştan sonra
  /// beklenmez; çağıran `settleIo` ile ya da kare kare ilerler.
  Future<void> pickView(WidgetTester tester, String label) async {
    final target = DeckView.values.firstWhere((v) => viewLabel(s, v) == label);
    expect(store.settings.deckView, isNot(target), reason: 'zaten bu görünümde');
    while (store.settings.deckView != target) {
      await tester.tap(find.byType(ViewModeButton));
      // Ayar dokunuşla birlikte değişir; hedefe varıldıysa beklemeden dönülür.
      if (store.settings.deckView == target) return;
      await settleIo(tester);
    }
  }

  /// Düzenleyicide kapalı duran bir bölümü ("Daha fazlası"ndaki düğmesiyle) açar.
  Future<void> openSection(WidgetTester tester, String label) async {
    final chip = find.widgetWithText(ActionChip, label);
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> addContainers(WidgetTester tester, int n) async {
    await tester.runAsync(() async {
      for (var i = 0; i < n; i++) {
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container));
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets('sağ üstteki çekmece simgesi çekmeceyi açar', (tester) async {
    await boot(tester);
    expect(find.text(s.drawerEmpty), findsNothing, reason: 'kapalı panel ekranda değil');
    await tester.tap(find.byTooltip(s.drawer));
    await tester.pumpAndSettle();
    expect(find.text(s.drawerEmpty), findsOneWidget);

    // Geri tuşu uygulamadan çıkmaz, paneli kapatır.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text(s.drawerEmpty), findsNothing);
    expect(find.text(s.appTitle), findsOneWidget);
  });

  testWidgets('sol menüdeki çekmece düğmesi de çekmeceyi açar', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(LeftDrawer), matching: find.byTooltip(s.drawer)));
    await tester.pumpAndSettle();
    expect(find.text(s.drawerEmpty), findsOneWidget);
  });

  testWidgets('sol menü telefonda kaydırmadan sığar; dört panel tek satırda, sayılarıyla', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      final kutu = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(kutu);
      await store.toggleFavorite(kutu.id);
      await store.commit(store.draft(parentId: Roots.drawer, kind: NodeKind.item).copyWith(name: 'Kablo'));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    final menu = find.byType(LeftDrawer);
    // Son satır (Ayarlar) ve altındaki toplam kaydırmadan görünür: menü 13 satıra çıkmış, sığmıyordu.
    expect(find.descendant(of: menu, matching: find.widgetWithText(ListTile, s.settings)).hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(find.text(s.totalRecords)).dy, lessThanOrEqualTo(860));
    for (final tip in [s.drawer, s.lostItems, s.favorites, s.expiredPanel]) {
      expect(find.descendant(of: menu, matching: find.byTooltip(tip)), findsOneWidget, reason: tip);
    }
    final row = tester.getTopLeft(find.descendant(of: menu, matching: find.byTooltip(s.drawer))).dy;
    expect(tester.getTopLeft(find.descendant(of: menu, matching: find.byTooltip(s.expiredPanel))).dy, row);
    // Sayılar simgenin köşesinde: sık kullanılan 1, çekmece 1.
    expect(find.descendant(of: find.descendant(of: menu, matching: find.byTooltip(s.favorites)), matching: find.text('1')),
        findsOneWidget);
    expect(find.descendant(of: menu, matching: find.widgetWithText(ListTile, s.inventories)), findsNothing,
        reason: 'envanterler başlıktan açılır');
  });

  testWidgets('gecikmemiş emanetin simgesi menüde ve "Bugün" şeridinde görünür renkte', (tester) async {
    await boot(tester);
    await tester.runAsync(() => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
          name: 'Matkap',
          borrowedTo: 'Ahmet',
          borrowedAt: DateTime.now(),
          returnDueAt: DateTime.now().add(const Duration(days: 7)),
        )));
    await tester.pumpAndSettle();
    final ink = Tones.of(tester.element(find.byType(HomeScreen))).ink;
    // Şeritte renksiz etiket (çekmece gibi): `tones.raised` koyu temada yazıyı zeminle aynı renge boyuyordu.
    final chip = find.descendant(of: find.byType(TodayStrip), matching: find.byIcon(Icons.front_hand_rounded));
    expect(tester.widget<Icon>(chip).color, ink);
    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    final menu = find.byType(LeftDrawer);
    final hand = tester.widget<Icon>(find.descendant(of: menu, matching: find.byIcon(Icons.front_hand_rounded)));
    // `tones.raised` açık temada simgeyi zeminle aynı renge boyuyordu.
    expect(hand.color, ink);
  });

  testWidgets('kartın damgaları (emanet, gecikti, SKT geçti) kartta ve satırda iki temada da okunur', (tester) async {
    await boot(tester);
    final now = DateTime.now();
    await tester.runAsync(() async {
      Node item(String name) => store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name);
      await store.commit(item('Matkap')
          .copyWith(borrowedTo: 'Ahmet', borrowedAt: now, returnDueAt: now.add(const Duration(days: 7))));
      await store.commit(item('Testere').copyWith(
          borrowedTo: 'Ayşe',
          borrowedAt: now.subtract(const Duration(days: 10)),
          returnDueAt: now.subtract(const Duration(days: 3))));
      await store.commit(item('Süt').copyWith(quantity: 1, expiresAt: DateTime(2020, 1, 1)));
    });
    double contrast(Color a, Color b) {
      final (x, y) = (a.computeLuminance(), b.computeLuminance());
      return (max(x, y) + 0.05) / (min(x, y) + 0.05);
    }

    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      for (final view in [DeckView.deck, DeckView.list]) {
        await tester.runAsync(() => store.updateSettings(store.settings.copyWith(themeMode: theme, deckView: view)));
        await tester.pumpAndSettle();
        for (final text in [s.borrowedToStamp('Ahmet'), s.borrowOverdueShort, s.expiredShort]) {
          final label = find.text(text).first;
          final ink = tester.widget<Text>(label).style!.color!;
          final stamp = tester.widget<Container>(find
              .ancestor(of: label, matching: find.byWidgetPredicate((w) => w is Container && w.decoration != null))
              .first);
          final paper = (stamp.decoration! as BoxDecoration).color!;
          // Koyu temada emanet damgası koyu üstüne koyuydu (1,1:1), kırmızılar açık kırmızı üstüne beyaz (2,5:1).
          expect(contrast(ink, paper), greaterThan(4.5), reason: '$text, $theme, $view');
        }
      }
    }
    await settleIo(tester);
  });

  testWidgets('emanet penceresinin Kaydet düğmesi sistem çubuğunun üstünde; yatayda kayınca ulaşılır', (tester) async {
    await boot(tester);
    // Jest çubuğu ya da üç düğme: 48 dp (uygulama kenardan kenara çizilir).
    tester.view.padding = const FakeViewPadding(bottom: 96);
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    await tester.runAsync(() => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
          name: 'Matkap',
          borrowedTo: 'Ahmet',
          borrowedAt: DateTime.now(),
          returnDueAt: DateTime.now().add(const Duration(days: 7)),
        )));
    await tester.pumpAndSettle();
    unawaited(Navigator.of(tester.element(find.byType(HomeScreen)))
        .push(MaterialPageRoute<void>(builder: (_) => const LendingPage())));
    await tester.pumpAndSettle();
    // Emanettekiler → ✎ → "Emanet bilgisi".
    await tester.tap(find.byTooltip(s.borrowDetailsTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(s.borrowDetailsTitle)));
    await tester.pumpAndSettle();
    final save = find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(FilledButton, s.save));
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(860 - 48), reason: 'düğme çubuğun altında kalmasın');

    // Yatay telefon: pencere ekrana sığmaz, kayar; düğmeye ulaşılır ve çalışır.
    tester.view.physicalSize = const Size(860, 411) * 2;
    await tester.pumpAndSettle();
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(411 - 48));
    await tester.tap(save);
    await settleIo(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text(s.borrowSuccess('Matkap', 'Ahmet')), findsOneWidget);
  });

  testWidgets('düzenleyicideki emanet penceresinin Kaydet düğmesi de sistem çubuğunun üstünde', (tester) async {
    await boot(tester);
    tester.view.padding = const FakeViewPadding(bottom: 96);
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    await tester.runAsync(() => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item)
        .copyWith(name: 'Matkap', borrowedTo: 'Ahmet', borrowedAt: DateTime.now())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matkap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.edit).last);
    await tester.pumpAndSettle();
    final row = find.text(s.borrowedPageTitle).last;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    final save = find.descendant(of: find.byType(BottomSheet), matching: find.widgetWithText(FilledButton, s.save));
    expect(tester.getRect(save).bottom, lessThanOrEqualTo(860 - 48));
    await tester.tap(find.byType(ModalBarrier).last, warnIfMissed: false);
    await settleIo(tester);
  });

  testWidgets('menüden ortak kullanım sayfası açılır', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, s.sharing));
    await tester.pumpAndSettle();
    expect(find.text(s.sharingOffTitle), findsOneWidget);
    expect(find.text(s.turnOnSharing), findsOneWidget);
  });

  /// Aynı satırda yan yana duran kart sayısının en büyüğü (satırlar sağa sola
  /// kaydığı için yalnızca x'e bakmak yetmez).
  Set<double> cardColumns(WidgetTester tester) {
    final rows = <double, Set<double>>{};
    for (final e in find.byType(NodeCard).evaluate()) {
      final at = tester.getTopLeft(find.byWidget(e.widget));
      (rows[at.dy.roundToDouble()] ??= {}).add(at.dx);
    }
    return rows.values.reduce((a, b) => a.length >= b.length ? a : b);
  }

  testWidgets('dar telefonda kartlar tek sütun', (tester) async {
    await boot(tester);
    await addContainers(tester, 4);
    expect(cardColumns(tester), hasLength(1));
  });

  testWidgets('tablette ve yatay ekranda kartlar sütunlara dizilir', (tester) async {
    await boot(tester, size: const Size(1280, 800));
    await addContainers(tester, 6);
    expect(cardColumns(tester), hasLength(3));
  });

  testWidgets('yatay telefonda iki sütun', (tester) async {
    await boot(tester, size: const Size(860, 400));
    await addContainers(tester, 4);
    expect(cardColumns(tester), hasLength(2));
    expect(tester.takeException(), isNull, reason: 'kısa ekranda taşma olmamalı');
  });

  testWidgets('yatay düzen: arama ve artı soldaki şeritte, paneller desteyi örtmeden yanında açılır', (tester) async {
    await boot(tester, size: const Size(860, 400));
    await addContainers(tester, 4);
    // Alttaki arama çubuğu yok; şeritte arama, QR ve yeni kayıt.
    expect(find.text(s.searchInventory), findsNothing);
    expect(find.byTooltip(s.search), findsOneWidget);
    expect(find.byTooltip(s.scanQr), findsOneWidget);
    expect(find.byTooltip(s.newRecord), findsOneWidget);
    // Sık kullanılan varken başlıkta düğmesi çıkar (sağ kenar kulbu yerine).
    Finder inHeader(Finder f) => find.descendant(of: find.byType(ShellHeader), matching: f);
    expect(inHeader(find.byTooltip(s.favorites)), findsNothing);
    await tester.runAsync(() => store.toggleFavorite(store.childrenOf(Roots.home).first.id));
    await tester.pumpAndSettle();
    expect(inHeader(find.byTooltip(s.favorites)), findsOneWidget);

    final deck = find.byKey(const ValueKey(Roots.home));
    final before = tester.getSize(deck).width;
    await tester.tap(find.byTooltip(s.drawer).first);
    await tester.pumpAndSettle();
    expect(find.text(s.drawerEmpty), findsOneWidget);
    expect(tester.getSize(deck).width, lessThan(before), reason: 'deste panelin yanına daralır');
    expect(find.byType(NodeListView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yatayda başlık tek satır, düzenleyici iki sütun: önizleme ve ad solda, bölümler sağda', (tester) async {
    await boot(tester, size: const Size(860, 400));
    expect(tester.getSize(find.byType(ShellHeader)).height, lessThan(70), reason: 'yatayda alçak başlık');
    await tester.tap(find.byTooltip(s.newRecord));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.addItem));
    await tester.pumpAndSettle();
    final name = find.byType(TextField).first;
    final section = find.text(s.upper(s.appearance));
    expect(tester.getCenter(name).dx, lessThan(tester.getCenter(section).dx));
    expect(tester.getTopLeft(section).dy, lessThan(300), reason: 'bölümler kaydırmadan görünür');
    // Not da solda, önizlemenin altında.
    final note = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == s.noteOptional);
    expect(tester.getCenter(note).dx, lessThan(tester.getCenter(section).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('kartın fotoğrafına dokununca tam ekran açılır; kartın kendisine dokunmak açmaz', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      await addPhotoItem('Matkap');
    });
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);

    // Destedeki kartın fotoğrafı.
    await tester.tap(find.byType(PinnedPhoto));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    // Geri tuşu da kapatır.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);

    // Kartın adına dokunmak odak görünümünü açar, fotoğrafı değil.
    await tester.tap(find.text('Matkap'));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
    // Odaktaki kartın fotoğrafı da açılır.
    await tester.tap(find.byType(PinnedPhoto).last);
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.descendant(of: find.byType(PhotoViewer), matching: find.text('Matkap')), findsOneWidget);
    // Çift dokunuş yakınlaştırır, ikincisi geri döner.
    double scale() => tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!.value.getMaxScaleOnAxis();
    Future<void> doubleTap() async {
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byType(InteractiveViewer));
      await tester.pumpAndSettle();
    }

    await doubleTap();
    expect(scale(), closeTo(2.5, 0.01));
    await doubleTap();
    expect(scale(), closeTo(1, 0.01));
    await tester.tap(find.byTooltip(s.close));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });

  testWidgets('düzenleyicide ad kartın başlığında yerinde değişir; ayrı ad kutusu yok', (tester) async {
    await boot(tester);
    late String id;
    await tester.runAsync(() async {
      final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap');
      await store.commit(n);
      id = n.id;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matkap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.edit).last);
    await tester.pumpAndSettle();

    final title = find.descendant(of: find.byType(NodeCard), matching: find.byType(TextField));
    expect(title, findsOneWidget, reason: 'ad kartın başlığında');
    expect(
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == s.name),
      findsNothing,
      reason: 'ayrı "Ad" kutusu yok',
    );
    expect(tester.widget<TextField>(title).controller!.text, 'Matkap');
    await tester.enterText(title, 'Darbeli matkap');
    await tester.tap(find.text(s.save));
    await settleIo(tester);
    expect(store.byId(id)!.name, 'Darbeli matkap');
  });

  testWidgets('yazı alanının dışına dokununca ya da kaydırınca yazma biter', (tester) async {
    await boot(tester);
    await tester.runAsync(() => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Matkap'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.edit).last);
    await tester.pumpAndSettle();
    final title = find.descendant(of: find.byType(NodeCard), matching: find.byType(TextField));
    bool editing() => tester.state<EditableTextState>(find.descendant(of: title, matching: find.byType(EditableText))).widget.focusNode.hasFocus;

    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(editing(), isTrue);
    // Boş bir yere (bölüm başlığına) dokununca.
    await tester.tap(find.text(s.upper(s.appearance)));
    await tester.pumpAndSettle();
    expect(editing(), isFalse, reason: 'dışarı dokununca imleç ve klavye gider');

    await tester.tap(title);
    await tester.pumpAndSettle();
    expect(editing(), isTrue);
    await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(editing(), isFalse, reason: 'kaydırınca da');
  });

  testWidgets('yeni eşyanın düzenleyicisi sade: not kartın altında, gerisi düğmelerle açılır', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip(s.newRecord));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.addItem));
    await tester.pumpAndSettle();

    // Her zaman açık: önizleme, not, görünüm, yer.
    final card = tester.getRect(find.byType(NodeCard));
    final note = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == s.noteOptional);
    expect(tester.getTopLeft(note).dy, greaterThan(card.bottom - 1));
    expect(tester.getTopLeft(note).dy, lessThan(tester.getTopLeft(find.text(s.upper(s.appearance))).dy));
    expect(find.text(s.upper(s.placeSection)), findsOneWidget);
    // Kapalı: adet, alışveriş, tarihler, ekler, diğer; her birinin düğmesi var.
    for (final closed in [s.quantity, s.shoppingList, s.datesSection, s.attachments, s.moreActions]) {
      expect(find.text(s.upper(closed)), findsNothing, reason: closed);
      expect(find.widgetWithText(ActionChip, closed), findsOneWidget, reason: closed);
    }

    // Düğmeye dokununca bölüm açılır, düğmesi kalkar.
    await openSection(tester, s.datesSection);
    expect(find.text(s.upper(s.datesSection)), findsOneWidget);
    expect(find.text(s.purchaseDate), findsOneWidget);
    expect(find.widgetWithText(ActionChip, s.datesSection), findsNothing);
    await openSection(tester, s.moreActions);
    expect(find.text(s.privateSwitchTitle), findsOneWidget);
  });

  testWidgets('bilgisi olan bölüm açık gelir; klasörde eşyaya özgü bölümler hiç yok', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Süt',
            quantity: 2,
            expiresAt: DateTime(2027, 1, 1),
            attachments: [Attachment(id: 'a', name: 'Fiş', addedAt: DateTime(2026), url: 'https://ornek.com/f')],
          ));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Süt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.edit).last);
    await tester.pumpAndSettle();
    for (final open in [s.quantity, s.datesSection, s.attachments]) {
      expect(find.text(s.upper(open)), findsOneWidget, reason: open);
      expect(find.widgetWithText(ActionChip, open), findsNothing, reason: open);
    }
    expect(find.widgetWithText(ActionChip, s.shoppingList), findsOneWidget, reason: 'ayarı kapalı: bölümü de kapalı');
    await tester.tap(find.byTooltip(s.cancel));
    await tester.pumpAndSettle();

    // Klasörde: adet, alışveriş ve tarihler yok; ekler ve diğer düğme olarak.
    await addContainers(tester, 1);
    await tester.tap(find.byTooltip(s.options).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.edit).last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, s.quantity), findsNothing);
    expect(find.widgetWithText(ActionChip, s.datesSection), findsNothing);
    expect(find.widgetWithText(ActionChip, s.attachments), findsOneWidget);
    expect(find.widgetWithText(ActionChip, s.moreActions), findsOneWidget);
  });

  testWidgets('yeni eşyada başlık boşken alacağı ad silik görünür', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip(s.newRecord));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.addItem));
    await tester.pumpAndSettle();
    final title = find.descendant(of: find.byType(NodeCard), matching: find.byType(TextField));
    expect(tester.widget<TextField>(title).decoration!.hintText, 'Adsız 1');
  });

  testWidgets('yatayda kısa kartın fotoğrafı kartın boyunca uzanır, dikeyde başlığın altında', (tester) async {
    await boot(tester, size: const Size(860, 400));
    await tester.runAsync(() => addPhotoItem('Matkap'));
    await tester.pumpAndSettle();
    final landscape = tester.getSize(find.byType(PinnedPhoto)).height;
    expect(landscape, greaterThan(110), reason: 'yatayda büyük');
    final card = tester.getRect(find.byType(NodeCard));
    final photo = tester.getRect(find.byType(PinnedPhoto));
    expect(photo.top - card.top, lessThan(30), reason: 'başlık çizgisinin altına sıkışmaz');
    expect(card.right - photo.right, greaterThan(60), reason: '⋯ ve + sütununa binmez');
  });

  test('deste ölçüleri ekrana göre', () {
    expect(DeckLayout.of(const BoxConstraints(maxWidth: 411, maxHeight: 700)).columns, 1);
    expect(DeckLayout.of(const BoxConstraints(maxWidth: 800, maxHeight: 1100)).columns, 2);
    expect(DeckLayout.of(const BoxConstraints(maxWidth: 1280, maxHeight: 700)).columns, 3);
    expect(DeckLayout.of(const BoxConstraints(maxWidth: 1280, maxHeight: 700), compact: true).columns, 1);
    final short = DeckLayout.of(const BoxConstraints(maxWidth: 860, maxHeight: 250));
    expect(short.cardHeight, lessThan(214), reason: 'yatay telefonda kart kısalır');
  });

  testWidgets('karşıdan gelen değişiklik zilde sayı olur, listeden kabul edilir', (tester) async {
    await boot(tester);
    await addContainers(tester, 1);
    final mutfak = store.childrenOf(Roots.home).single;
    final later = DateTime.now().add(const Duration(seconds: 1));
    final incoming = Node(
      id: 'tencere',
      parentId: mutfak.id,
      kind: NodeKind.item,
      name: 'Tencere',
      color: 0xFF2E8B72,
      sortIndex: 0,
      createdAt: later,
      updatedAt: later,
      updatedBy: 'ali',
    );
    await tester.runAsync(() => store.mergeRemote(
          nodes: {incoming.id: incoming},
          tombstones: const {},
          review: true,
        ));
    await tester.pumpAndSettle();

    expect(store.byId('tencere'), isNull, reason: 'onaysız uygulanmaz');
    expect(find.text(s.newChangesFrom(s.someone, 1)), findsOneWidget, reason: 'bildirim');
    final bell = find.byTooltip(s.pendingChanges(1));
    expect(bell, findsOneWidget);
    expect(find.descendant(of: bell, matching: find.text('1')), findsOneWidget);
    expect(find.byType(PendingDot), findsOneWidget, reason: 'klasörün kartında işaret');

    await tester.tap(bell);
    await tester.pumpAndSettle();
    expect(find.text('Tencere'), findsOneWidget);
    expect(find.textContaining(s.changeAdded(s.someone), findRichText: true), findsOneWidget);

    await tester.tap(find.text(s.accept));
    await settleIo(tester);
    expect(store.byId('tencere'), isNotNull);
    expect(find.text(s.noPendingChanges), findsOneWidget);
  });

  testWidgets('yerinde olmayan eşya kayıp çekmecesine gider, yerini bilen geri koyar', (tester) async {
    await boot(tester);
    late Node pil;
    late Node kutu;
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      kutu = store.byId(k.id)!;
      final p = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil');
      await store.commit(p);
      pil = store.byId(p.id)!;
    });
    await tester.pumpAndSettle();

    // Eşyaya dokununca seçenekler açılır → "Yerinde yok".
    await tester.tap(find.text('Pil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.notThere));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.reportLost));
    await settleIo(tester);
    expect(store.byId(pil.id)!.isLost, isTrue);

    // Sağ kenarda kayıp kulbu çıkar (yalnızca kayıp varken); panel kayıp eşyayı gösterir.
    await tester.tap(find.byTooltip(s.lostDrawer));
    await tester.pumpAndSettle();
    expect(find.text(s.upper(s.lostWaiting(1))), findsOneWidget);
    expect(find.text(s.lastSeenIn(s.home)), findsOneWidget);

    // Yerini biliyorum → son görüldüğü yerde (ana ekran) açılır, Kutu'ya girilip taşınır.
    await tester.tap(find.text('Pil').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.iKnowWhere));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kutu').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.moveHere));
    await tester.pumpAndSettle();
    await settleIo(tester);
    expect(store.byId(pil.id)!.isLost, isFalse);
    expect(store.byId(pil.id)!.parentId, kutu.id);
  });

  testWidgets('klasörler ve eşyalar karışmaz: klasörler önce, eşyalar ayrı grupta', (tester) async {
    await boot(tester, size: const Size(1280, 800));
    await tester.runAsync(() async {
      // Karışık sırayla eklenir.
      for (final (name, kind) in [
        ('Pil', NodeKind.item),
        ('Kutu', NodeKind.container),
        ('Makas', NodeKind.item),
        ('Dolap', NodeKind.container),
      ]) {
        await store.commit(store.draft(parentId: Roots.home, kind: kind).copyWith(name: name));
      }
    });
    await tester.pumpAndSettle();

    expect(store.childrenOf(Roots.home).map((n) => n.name), ['Kutu', 'Dolap', 'Pil', 'Makas']);
    Offset at(String name) => tester.getTopLeft(find.text(name));
    // Geniş ekranda eşyalar klasörlerin satırına girmez, yeni satırdan başlar.
    expect(at('Dolap').dy, closeTo(at('Kutu').dy, 1));
    expect(at('Pil').dy, greaterThan(at('Kutu').dy + 20));
    expect(at('Pil').dx, closeTo(at('Kutu').dx, 5), reason: 'aynı sütun, satırlar biraz kayık');
    expect(find.text(s.items), findsOneWidget, reason: 'eşya grubunun etiketi');
  });

  testWidgets('karttaki ⋯ düğmesi seçenekleri açar', (tester) async {
    await boot(tester);
    await addContainers(tester, 1);
    await tester.tap(find.byTooltip(s.options));
    await tester.pumpAndSettle();
    expect(find.text(s.notThere), findsOneWidget);
    expect(find.byTooltip(s.edit), findsWidgets);
  });

  testWidgets('birden çok değişiklik listelenir, tümü tek dokunuşla kabul edilir', (tester) async {
    await boot(tester);
    final later = DateTime.now().add(const Duration(seconds: 1));
    Node item(String id, String name) => Node(
          id: id,
          parentId: null,
          kind: NodeKind.item,
          name: name,
          color: 0xFF2E8B72,
          sortIndex: 0,
          createdAt: later,
          updatedAt: later,
          updatedBy: 'ali',
        );
    await tester.runAsync(() => store.mergeRemote(
          nodes: {'a': item('a', 'Tencere'), 'b': item('b', 'Makas')},
          tombstones: const {},
          review: true,
        ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.pendingChanges(2)));
    await tester.pumpAndSettle();

    expect(find.text('Tencere'), findsOneWidget);
    expect(find.text('Makas'), findsOneWidget);
    final button = find.text('${s.acceptAll} (2)');
    expect(button, findsOneWidget);
    expect(tester.getCenter(button).dy, greaterThan(tester.view.physicalSize.height / 2 / 2),
        reason: 'düğme ekranın altında');
    await tester.tap(button);
    await settleIo(tester);
    expect(store.pendingCount, 0);
    expect(store.byId('a'), isNotNull);
    expect(store.byId('b'), isNotNull);
  });

  testWidgets('kartın simgesi listeden seçilir ve kartta görünür', (tester) async {
    await boot(tester);
    await addContainers(tester, 1);
    final kutu = store.childrenOf(Roots.home).single;
    await tester.tap(find.byTooltip(s.options));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.edit).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.icon));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.kitchen_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await settleIo(tester);
    expect(store.byId(kutu.id)!.icon, 'kitchen');
    expect(find.byIcon(Icons.kitchen_rounded), findsWidgets);
  });

  testWidgets('uzun basıp bırakmak seçenek açmaz, sağ üstteki çekmece simgesi aç/kapat çalışır', (tester) async {
    await boot(tester);
    await addContainers(tester, 1);
    await tester.longPress(find.byType(NodeCard).first);
    await tester.pumpAndSettle();
    expect(find.text(s.notThere), findsNothing, reason: 'uzun basmak yalnızca taşıma');
    expect(store.draggingId, isNull, reason: 'bırakınca taşıma biter');

    await tester.tap(find.byTooltip(s.drawer));
    await tester.pumpAndSettle();
    expect(find.text(s.drawerEmpty), findsOneWidget);
    await tester.tap(find.byTooltip(s.drawer));
    await tester.pumpAndSettle();
    expect(find.text(s.drawerEmpty), findsNothing, reason: 'ikinci dokunuş kapatır');
  });

  testWidgets('kartlar dalga gibi adım adım sağa, sonra sola kayar', (tester) async {
    await boot(tester, size: const Size(411, 2400));
    await addContainers(tester, 9);
    final xs = [for (final e in find.byType(NodeCard).evaluate()) tester.getTopLeft(find.byWidget(e.widget)).dx];
    expect(xs, hasLength(9));
    final steps = [for (var i = 1; i < xs.length; i++) (xs[i] - xs[i - 1]).roundToDouble()];
    expect(steps, [4, 4, -4, -4, -4, -4, 4, 4], reason: '0, +4, +8, +4, 0, -4, -8, -4, 0');
  });

  testWidgets('fotoğraf düzeni değiştirmez: ⋯, + ve ad fotoğrafsız karttaki yerinde', (tester) async {
    await boot(tester);
    late String photoId;
    late String plainId;
    await tester.runAsync(() async {
      final dir = Directory.systemTemp.createTempSync('envanter_photo');
      AppPaths.useDirectory(dir.path);
      final bytes = File('test/fixtures/visual/stored_kutu.jpg').readAsBytesSync();
      File('${dir.path}/images/kutu.jpg').writeAsBytesSync(bytes);
      final a = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Fotoğraflı', imagePath: 'images/kutu.jpg');
      final b = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Düz');
      await store.commit(a);
      await store.commit(b);
      photoId = a.id;
      plainId = b.id;
    });
    await tester.pumpAndSettle();

    Finder inCard(String name, Finder f) =>
        find.descendant(of: find.ancestor(of: find.text(name), matching: find.byType(NodeCard)), matching: f);
    double right(Finder f) => tester.getTopRight(f).dx;
    double cardRight(String name) =>
        tester.getTopRight(find.ancestor(of: find.text(name), matching: find.byType(NodeCard))).dx;

    final photoMore = cardRight('Fotoğraflı') - right(inCard('Fotoğraflı', find.byTooltip(s.options)));
    final plainMore = cardRight('Düz') - right(inCard('Düz', find.byTooltip(s.options)));
    expect(photoMore, closeTo(plainMore, 0.5));
    final photoPlus = cardRight('Fotoğraflı') - right(inCard('Fotoğraflı', find.byTooltip(s.addInside)));
    final plainPlus = cardRight('Düz') - right(inCard('Düz', find.byTooltip(s.addInside)));
    expect(photoPlus, closeTo(plainPlus, 0.5));
    expect(store.byId(photoId)!.hasImage && !store.byId(plainId)!.hasImage, isTrue);
    // ⋯ düğmesi iki kartta da aynı yükseklikte (üst satır hizası).
    final photoMoreTop = tester.getTopLeft(inCard('Fotoğraflı', find.byTooltip(s.options))).dy -
        tester.getTopLeft(find.ancestor(of: find.text('Fotoğraflı'), matching: find.byType(NodeCard))).dy;
    final plainMoreTop = tester.getTopLeft(inCard('Düz', find.byTooltip(s.options))).dy -
        tester.getTopLeft(find.ancestor(of: find.text('Düz'), matching: find.byType(NodeCard))).dy;
    expect(photoMoreTop, closeTo(plainMoreTop, 0.5));
    // Ad da aynı yerden başlar; fotoğraf tıklamaları engellemez.
    double nameLeft(String name) =>
        tester.getTopLeft(find.text(name)).dx - tester.getTopLeft(find.ancestor(of: find.text(name), matching: find.byType(NodeCard))).dx;
    expect(nameLeft('Fotoğraflı'), closeTo(nameLeft('Düz'), 0.5));
    expect(find.byType(PinnedPhoto), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adet tutulan eşya kartta − / + ile değişir; 0 olunca kayıt durur, "Tükendi" yazar', (tester) async {
    await boot(tester);
    late String id;
    await tester.runAsync(() async {
      final pil = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil', quantity: 2);
      await store.commit(pil);
      id = pil.id;
    });
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip(s.decrease));
    await settleIo(tester);
    expect(store.byId(id)!.quantity, 1);
    await tester.tap(find.byTooltip(s.decrease));
    await settleIo(tester);
    expect(store.byId(id)!.quantity, 0);
    expect(store.byId(id), isNotNull, reason: '0 olunca silinmez');
    expect(find.text(s.outOfStock), findsOneWidget);

    // 0'da azaltma kapalı; artırınca stok yenilenir.
    await tester.tap(find.byTooltip(s.decrease));
    await settleIo(tester);
    expect(store.byId(id)!.quantity, 0);
    await tester.tap(find.byTooltip(s.increase));
    await settleIo(tester);
    expect(store.byId(id)!.quantity, 1);
    expect(find.text(s.outOfStock), findsNothing);
  });

  testWidgets('adet tutulmayan eşyada − / + görünmez', (tester) async {
    await boot(tester);
    await tester.runAsync(() => store.commit(
          store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Makas'),
        ));
    await tester.pumpAndSettle();
    expect(find.byTooltip(s.increase), findsNothing);
  });

  testWidgets('not kartın üstünde yazar, uzunsa kesilir', (tester) async {
    await boot(tester);
    final long = List.filled(40, 'uzun bir not').join(' ');
    await tester.runAsync(() => store.commit(
          store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Kutu', note: long),
        ));
    await tester.pumpAndSettle();
    final note = tester.widget<Text>(find.text(long));
    expect(note.overflow, TextOverflow.ellipsis);
    expect(note.maxLines, inInclusiveRange(1, 5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('düzenleyicide adet tutmaya başlanır ve bırakılır', (tester) async {
    await boot(tester);
    late String id;
    await tester.runAsync(() async {
      final d = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Vida');
      await store.commit(d);
      id = d.id;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.options));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.edit).last);
    await tester.pumpAndSettle();
    // Adedi tutulmayan eşyada bölüm kapalı gelir.
    expect(find.byTooltip(s.increase), findsNothing);
    await openSection(tester, s.quantity);
    await tester.tap(find.byTooltip(s.increase).first);
    await tester.pumpAndSettle();
    expect(find.text(s.stopCounting), findsOneWidget);
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await settleIo(tester);
    expect(store.byId(id)!.quantity, 2);
  });

  testWidgets('en az adet düzenleyicide açılır; adet ona inince kartta "Azaldı" çıkar', (tester) async {
    await boot(tester);
    late String id;
    await tester.runAsync(() async {
      final d = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Deterjan', quantity: 3);
      await store.commit(d);
      id = d.id;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.options));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.edit).last);
    await tester.pumpAndSettle();
    // Adedi tutulan eşyada bölüm açık gelir (görünüm ve yerin altında).
    expect(find.text(s.minQuantityOff), findsOneWidget);
    await tester.ensureVisible(find.text(s.minQuantityOff));
    await tester.pumpAndSettle();
    // İkinci sayaç en az adet: ilk dokunuş 1'de açar, sonra artar.
    await tester.tap(find.byTooltip(s.increase).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.increase).at(1));
    await tester.pumpAndSettle();
    expect(find.text(s.minQuantityOn(2)), findsOneWidget);
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await settleIo(tester);
    expect((store.byId(id)!.quantity, store.byId(id)!.minQuantity), (3, 2));
    expect(find.text(s.lowStockShort), findsNothing);

    await tester.tap(find.byTooltip(s.decrease));
    await settleIo(tester);
    expect(find.text(s.lowStockShort), findsOneWidget);
    // Listeye kendiliğinden girmez (otomatik ekleme kapalı); bildirim eklemeyi önerir.
    expect(store.shoppingItems, isEmpty);
    expect(store.shoppingSuggestions.single.id, id);
    expect(find.text(s.runningLow('Deterjan')), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, s.addToListShort));
    await settleIo(tester);
    expect(store.shoppingItems.single.id, id);
  });

  testWidgets('kartın menüsünden alışveriş listesine eklenir ve çıkarılır', (tester) async {
    await boot(tester);
    late String id;
    await tester.runAsync(() async {
      final d = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Ampul');
      await store.commit(d);
      id = d.id;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.options));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.addToShopping));
    await settleIo(tester);
    expect(store.byId(id)!.isWanted, isTrue);
    expect(find.text(s.addedToShopping('Ampul')), findsOneWidget);
    await tester.tap(find.byTooltip(s.options));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.removeFromShopping));
    await settleIo(tester);
    expect(store.byId(id)!.isWanted, isFalse);
  });

  /// Kartı uzun basıp tutar, parmağı biraz kıpırdatır; sürükleme başlar.
  Future<TestGesture> pickUp(WidgetTester tester, String name) async {
    final g = await tester.startGesture(tester.getCenter(find.text(name).first));
    await tester.pump(const Duration(milliseconds: 400));
    await g.moveBy(const Offset(0, -30));
    await tester.pump();
    await g.moveBy(const Offset(0, -30));
    await tester.pump();
    return g;
  }

  Future<(String, String)> boxWithBattery(WidgetTester tester, {bool inside = false}) async {
    late String kutu;
    late String pil;
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      kutu = k.id;
      final p = store.draft(parentId: inside ? k.id : Roots.home, kind: NodeKind.item).copyWith(name: 'Pil');
      await store.commit(p);
      pil = p.id;
    });
    await tester.pumpAndSettle();
    return (kutu, pil);
  }

  testWidgets('düzenleyicide yalnızca yer değişince de vazgeçerken sorulur', (tester) async {
    await boot(tester);
    final (_, pil) = await boxWithBattery(tester);
    await tester.tap(find.text('Pil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.edit).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(s.placementHint));
    await tester.tap(find.text(s.placementHint));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Kutu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.moveHere));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.cancel));
    await tester.pumpAndSettle();
    expect(find.text(s.discardChangesQuestion), findsOneWidget, reason: 'yer değişikliği sessizce gitmesin');
    expect(store.byId(pil)!.parentId, isNull);
  });

  testWidgets('karta dokununca en sık dört eylem kartın altında yan yana; gerisi kısa liste', (tester) async {
    await boot(tester);
    final (kutu, pil) = await boxWithBattery(tester);

    // Eşya: Düzenle, Taşı, Sık kullanılan, Listeye ekle.
    await tester.tap(find.text('Pil'));
    await tester.pumpAndSettle();
    final quick = [s.edit, s.quickMove, s.quickFavorite, s.quickShop];
    final tops = [for (final label in quick) tester.getCenter(find.text(label).last).dy];
    expect(tops.toSet().length, 1, reason: 'dördü aynı satırda');
    expect(find.text(s.changePlacement), findsNothing, reason: 'uzun adı ipucunda');
    expect(find.byTooltip(s.changePlacement), findsOneWidget);
    // Listede kalanlar onların altında.
    expect(tester.getCenter(find.text(s.notThere)).dy, greaterThan(tops.first));
    expect(find.text(s.moveToTrash), findsOneWidget);

    // Sık kullanılana eklenince düğme yerinde kalır, ipucu "çıkar" olur.
    await tester.tap(find.byTooltip(s.addFavorite));
    await settleIo(tester);
    expect(store.isFavorite(pil), isTrue);
    await tester.tap(find.text('Pil').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip(s.removeFavorite), findsOneWidget);
    // Alışveriş listesi de aynı satırdan.
    await tester.tap(find.byTooltip(s.addToShopping));
    await settleIo(tester);
    expect(store.byId(pil)!.isWanted, isTrue);
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).hideCurrentSnackBar();
    await tester.pumpAndSettle();

    // Klasörde dördüncü düğme QR kod (alışveriş yok).
    await tester.tap(find.descendant(of: find.widgetWithText(NodeCard, 'Kutu'), matching: find.byTooltip(s.options)));
    await tester.pumpAndSettle();
    expect(find.byTooltip(s.addToShopping), findsNothing);
    expect(find.text(s.qrCode), findsOneWidget);
    await tester.tap(find.byTooltip(s.changePlacement));
    await tester.pumpAndSettle();
    expect(find.text(s.whereShouldGo(store.nameOf(store.byId(kutu)!))), findsOneWidget, reason: 'yer seçici açıldı');
  });

  testWidgets('⋯ → "Yalnızca bende tut": kartta kilit çıkar, kayıt karşıya gitmez', (tester) async {
    await boot(tester);
    final (kutu, pil) = await boxWithBattery(tester, inside: true);
    await tester.tap(find.descendant(of: find.widgetWithText(NodeCard, 'Kutu'), matching: find.byTooltip(s.options)));
    await tester.pumpAndSettle();
    // Seyrek kullanılanlar "Diğer"in altında.
    expect(find.text(s.keepPrivate), findsNothing);
    await tester.tap(find.text(s.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.keepPrivate));
    await settleIo(tester);
    expect(store.isPrivate(kutu), isTrue);
    expect(store.isPrivate(pil), isTrue);
    expect(find.byTooltip(s.privateHint), findsOneWidget);
    expect(find.text(s.markedPrivate('Kutu', wasShared: false)), findsOneWidget);
    expect(store.snapshot().nodes, isEmpty);

    // Aynı yerden geri alınır (önceki bildirim menünün alt satırlarını örtmesin).
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.widgetWithText(NodeCard, 'Kutu'), matching: find.byTooltip(s.options)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.makeShared));
    await settleIo(tester);
    expect(store.isPrivate(kutu), isFalse);
    expect(find.byTooltip(s.privateHint), findsNothing);
  });

  testWidgets('son kullanma yaklaşınca kartta damga, menüde sayı, listede bölüm', (tester) async {
    await boot(tester);
    final today = DateTime.now();
    await tester.runAsync(() async {
      await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Süt',
            purchasedAt: DateTime(today.year, today.month, today.day - 9),
            expiresAt: DateTime(today.year, today.month, today.day + 3),
          ));
      await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Matkap',
            purchasedAt: DateTime(2026, 1, 10),
            warranty: '2y',
          ));
    });
    await tester.pumpAndSettle();
    expect(find.text(s.expiringShort), findsOneWidget);

    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, s.datesPage));
    await tester.pumpAndSettle();
    expect(find.text(s.upper(s.expiringSection)), findsOneWidget);
    expect(find.text(s.upper(s.warrantySection)), findsOneWidget);
    expect(find.textContaining(s.daysLeft(3)), findsOneWidget);
    expect(find.textContaining(s.warrantyUntil(s.formatDate(DateTime(2028, 1, 10)))), findsOneWidget);
  });

  testWidgets('tükenen öneri olarak görünür; markette "Aldım" işaretler, evde "Yerleştir" adedi girer', (tester) async {
    await boot(tester);
    late String pil;
    await tester.runAsync(() async {
      final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil', quantity: 0);
      await store.commit(n);
      pil = n.id;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, s.shoppingList));
    await tester.pumpAndSettle();
    expect(find.text(s.upper(s.suggestionsSection)), findsOneWidget);
    expect(find.text(s.upper(s.toBuySection)), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, s.addShort));
    await settleIo(tester);
    expect(find.text(s.upper(s.toBuySection)), findsOneWidget);
    expect(find.text(s.upper(s.suggestionsSection)), findsNothing);

    // Markette: adet sorulmaz, "Yerleştirilecek"e geçer.
    await tester.tap(find.widgetWithText(FilledButton, s.bought));
    await settleIo(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(s.upper(s.toBuySection)), findsNothing);
    expect(find.text(s.upper(s.putAwaySection)), findsOneWidget);
    expect(store.byId(pil)!.quantity, 0);

    // Evde: kaç tane alındığı.
    await tester.tap(find.widgetWithText(FilledButton, s.putAway));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '6');
    await tester.tap(find.widgetWithText(FilledButton, s.bought).last);
    await settleIo(tester);
    expect(store.byId(pil)!.quantity, 6);
    expect(store.byId(pil)!.isBought, isFalse);
    expect(find.text(s.shoppingEmpty), findsOneWidget);
  });

  testWidgets('düzenleyicide raf ömrü seçilir; satın alma tarihiyle son kullanma hesaplanır', (tester) async {
    await boot(tester);
    late String muz;
    await tester.runAsync(() async {
      final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Muz',
            purchasedAt: DateTime(2026, 9, 20),
          );
      await store.commit(n);
      muz = n.id;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.edit).last);
    await tester.pumpAndSettle();

    final editorScroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
    await tester.scrollUntilVisible(find.text(s.shelfLife), 300, scrollable: editorScroll);
    // Kenarda yarım kalmasın (dokunuş boşa gitmesin): tamamen görünür olsun.
    await tester.ensureVisible(find.text(s.shelfLife));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.shelfLife));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '1 hafta'));
    await tester.pumpAndSettle();
    expect(find.text(s.calculated(s.formatDate(DateTime(2026, 9, 27)))), findsOneWidget);

    await tester.tap(find.text(s.save).first);
    await settleIo(tester);
    expect(store.byId(muz)!.shelfLife, '1w');
    expect(store.byId(muz)!.effectiveExpiry, DateTime(2026, 9, 27));
  });

  testWidgets('sürüklerken "Vazgeç" noktasına bırakılan kart yerinde kalır', (tester) async {
    await boot(tester);
    final (_, pil) = await boxWithBattery(tester);
    expect(find.text(s.cancelDrag), findsNothing, reason: 'yalnızca sürüklerken görünür');

    final g = await pickUp(tester, 'Pil');
    expect(store.draggingId, pil);
    expect(find.text(s.cancelDrag), findsOneWidget);
    expect(find.text(s.upOneLevel), findsNothing, reason: 'ana ekranda üst seviye yok');
    await g.moveTo(tester.getCenter(find.text(s.cancelDrag)));
    await tester.pump();
    await g.up();
    await settleIo(tester);

    expect(store.draggingId, isNull);
    expect(store.byId(pil)!.parentId, isNull);
    expect(store.byId(pil)!.inDrawer, isFalse);
    expect(find.text(s.cancelDrag), findsNothing);
  });

  testWidgets('klasörün içinden "Bir üst seviye"ye bırakılan kart bir üste taşınır', (tester) async {
    await boot(tester);
    final (kutu, pil) = await boxWithBattery(tester, inside: true);
    await tester.tap(find.text('Kutu'));
    await tester.pumpAndSettle();
    expect(store.byId(pil)!.parentId, kutu);

    final g = await pickUp(tester, 'Pil');
    expect(find.text(s.upOneLevel), findsOneWidget);
    await g.moveTo(tester.getCenter(find.text(s.upOneLevel)));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await settleIo(tester);

    expect(store.byId(pil)!.parentId, isNull, reason: 'Kutu’nun durduğu yere, ana ekrana');
  });

  testWidgets('"Bir üst seviye" üzerinde beklenince yerinde bir üste çıkılır', (tester) async {
    await boot(tester);
    final (kutu, pil) = await boxWithBattery(tester, inside: true);
    await tester.tap(find.text('Kutu'));
    await tester.pumpAndSettle();

    final g = await pickUp(tester, 'Pil');
    await g.moveTo(tester.getCenter(find.text(s.upOneLevel)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    // Başlık artık ana ekran; ana ekranın kartları görünüyor, üst seviye noktası yok.
    expect(find.text(s.appTitle), findsWidgets);
    expect(find.text(s.upOneLevel), findsNothing);
    // Vazgeçince hiçbir şey taşınmaz.
    await g.moveTo(tester.getCenter(find.text(s.cancelDrag)));
    await tester.pump();
    await g.up();
    await settleIo(tester);
    expect(store.byId(pil)!.parentId, kutu);
  });

  testWidgets('kartı sola kaydırmak çöp kutusuna atar, geri alınabilir', (tester) async {
    await boot(tester);
    final (_, pil) = await boxWithBattery(tester);

    await tester.fling(find.text('Pil'), const Offset(-300, 0), 1400);
    // Kart kayıp gider, sonra kayıt yazılır ve bildirim çıkar.
    await settleIo(tester);
    await settleIo(tester);
    expect(store.byId(pil)!.isDeleted, isTrue);

    await tester.tap(find.text(s.undo));
    await settleIo(tester);
    expect(store.byId(pil)!.isDeleted, isFalse, reason: 'geri alınınca kayıt döner');
  });

  testWidgets('kartı sağa kaydırmak çekmeceye alır', (tester) async {
    await boot(tester);
    final (kutu, pil) = await boxWithBattery(tester, inside: true);
    await tester.tap(find.text('Kutu'));
    await tester.pumpAndSettle();
    expect(store.byId(pil)!.parentId, kutu);

    await tester.fling(find.text('Pil'), const Offset(300, 0), 1400);
    await settleIo(tester);
    await settleIo(tester);
    expect(store.byId(pil)!.inDrawer, isTrue);
    expect(store.byId(pil)!.parentId, isNull);
    expect(store.byId(pil)!.isDeleted, isFalse);
  });

  testWidgets('kısa kaydırma eylemi çalıştırmaz, kart yerinde kalır', (tester) async {
    await boot(tester);
    final (_, pil) = await boxWithBattery(tester);

    // Eşiğin altında, yavaş: kart yerine döner.
    await tester.drag(find.text('Pil'), const Offset(-40, 0));
    await settleIo(tester);
    expect(store.byId(pil)!.isDeleted, isFalse);
    expect(store.byId(pil)!.inDrawer, isFalse);
  });

  testWidgets('sürüklenen kart alt kenarda beklerken deste kendiliğinden kayar', (tester) async {
    await boot(tester);
    await addContainers(tester, 12);
    double offset() => tester.widget<StackedCardList>(find.byType(StackedCardList)).controller!.offset;
    expect(offset(), 0);

    final g = await pickUp(tester, '1');
    // Destenin alt kenarı: sürükleme noktalarının hemen üstü.
    await g.moveTo(const Offset(200, 760));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(offset(), greaterThan(0), reason: 'kenarda beklerken deste kaydı');

    // Kenarda beklerken altından geçen klasörün içine girilmez.
    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.text(s.appTitle), findsWidgets, reason: 'seviye değişmedi');

    // Vazgeçince hiçbir şey taşınmaz.
    await g.moveTo(tester.getCenter(find.text(s.cancelDrag)));
    await tester.pump();
    await g.up();
    await settleIo(tester);
  });

  testWidgets('klasör dolu işaretlenir, kartta damga çıkar', (tester) async {
    await boot(tester);
    await addContainers(tester, 1);
    expect(find.text(s.empty), findsOneWidget);

    await tester.tap(find.byTooltip(s.options).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.markFull));
    await settleIo(tester);
    expect(find.text(s.fullShort), findsOneWidget);
    expect(find.text(s.empty), findsNothing, reason: '"Dolu" ile "boş" bir arada yazmaz');

    await tester.tap(find.byTooltip(s.options).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.markNotFull));
    await settleIo(tester);
    expect(find.text(s.fullShort), findsNothing);
    expect(find.text(s.empty), findsOneWidget);
  });

  testWidgets('gruplama ayarı kapatılınca kartlar tek sırada, eklenme sırasında durur', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      for (final (name, kind) in [
        ('Pil', NodeKind.item),
        ('Kutu', NodeKind.container),
      ]) {
        await store.commit(store.draft(parentId: Roots.home, kind: kind).copyWith(name: name));
      }
    });
    await tester.pumpAndSettle();
    expect(store.childrenOf(Roots.home).map((n) => n.name), ['Kutu', 'Pil']);
    expect(find.text(s.items), findsOneWidget, reason: 'eşya grubunun etiketi');

    await tester.runAsync(() => store.updateSettings(store.settings.copyWith(groupKinds: false)));
    await tester.pumpAndSettle();
    expect(store.childrenOf(Roots.home).map((n) => n.name), ['Pil', 'Kutu'], reason: 'tek sıra');
    expect(find.text(s.items), findsNothing, reason: 'grup kalmadı');
  });

  testWidgets('sürüklenen kart bir kartın üst kenarına bırakılınca o sıraya girer', (tester) async {
    await boot(tester);
    await addContainers(tester, 3);
    List<String> order() => store.childrenOf(Roots.home).map(store.nameOf).toList();
    expect(order(), ['1', '2', '3']);

    final g = await pickUp(tester, '3');
    final first = find.ancestor(of: find.text('1'), matching: find.byType(NodeCardTile)).first;
    // Kartın üst şeridi: sıralama bölgesi.
    await g.moveTo(tester.getTopLeft(first) + const Offset(120, 8));
    await tester.pump();
    await g.up();
    await settleIo(tester);

    expect(order(), ['3', '1', '2'], reason: '"1"in önüne girdi');
  });

  testWidgets('kart klasörün ortasına bırakılınca içine girer (sıralama değil)', (tester) async {
    await boot(tester);
    final (kutu, pil) = await boxWithBattery(tester);
    final g = await pickUp(tester, 'Pil');
    final box = find.ancestor(of: find.text('Kutu'), matching: find.byType(NodeCardTile)).first;
    await g.moveTo(tester.getCenter(box));
    await tester.pump();
    await g.up();
    await settleIo(tester);
    await settleIo(tester);

    expect(store.byId(pil)!.parentId, kutu);
  });

  testWidgets('kayıt sık kullanılanlara eklenir, çekmecesinde görünür', (tester) async {
    await boot(tester);
    final (kutu, _) = await boxWithBattery(tester);

    // Önce boş: menüden açılır, ne olduğunu anlatır.
    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(LeftDrawer), matching: find.byTooltip(s.favorites)));
    await tester.pumpAndSettle();
    expect(find.text(s.favoritesEmpty), findsOneWidget);
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(s.options).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.addFavorite));
    await settleIo(tester);
    expect(store.isFavorite(kutu), isTrue);

    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(LeftDrawer), matching: find.byTooltip(s.favorites)));
    await tester.pumpAndSettle();
    expect(find.text(s.favoritesEmpty), findsNothing);
    expect(find.text(s.upper(s.recordCount(1))), findsWidgets, reason: 'panelde bir kayıt');
    expect(find.text(s.home), findsWidgets, reason: 'kaydın durduğu yer alt yazıda');
  });

  testWidgets('sık kullanılan varken sağ kenarda kulbu çıkar, tek dokunuşla açılır', (tester) async {
    await boot(tester);
    final (kutu, _) = await boxWithBattery(tester);
    final handle = find.descendant(of: find.byType(DrawerEdge), matching: find.byTooltip(s.favorites));
    expect(handle, findsNothing, reason: 'sık kullanılan yokken kenar sade');

    await tester.runAsync(() => store.toggleFavorite(kutu));
    await tester.pumpAndSettle();
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(find.text(s.upper(s.recordCount(1))), findsWidgets, reason: 'panel açıldı, bir kayıt');
    await settleIo(tester);
  });

  testWidgets('tarihi geçen varken sağ kenarda kulbu çıkar; panelde yerinden kıpırdamadan görünür', (tester) async {
    await boot(tester);
    final (kutu, _) = await boxWithBattery(tester);
    final handle = find.descendant(of: find.byType(DrawerEdge), matching: find.byTooltip(s.expiredPanel));
    expect(handle, findsNothing, reason: 'tarihi geçen yokken kulp yok');

    late String sut;
    await tester.runAsync(() async {
      final n = store.draft(parentId: kutu, kind: NodeKind.item).copyWith(
            name: 'Süt',
            expiresAt: DateTime.now().subtract(const Duration(days: 3)),
          );
      await store.commit(n);
      sut = n.id;
    });
    await tester.pumpAndSettle();
    await tester.tap(handle);
    await tester.pumpAndSettle();
    expect(find.text(s.upper(s.recordCount(1))), findsWidgets, reason: 'panel açıldı, bir kayıt');
    expect(find.text('Süt'), findsWidgets);
    expect(store.byId(sut)!.parentId, kutu);

    // Çöpe atılınca alandan da, kenardan da düşer.
    await tester.runAsync(() => store.moveToTrash(sut));
    await tester.pumpAndSettle();
    expect(store.expiredItems, isEmpty);
    await settleIo(tester);
  });

  testWidgets('düzenleyicide "listeye kendiliğinden ekle" açılınca biten eşya listeye girer', (tester) async {
    await boot(tester);
    late String id;
    await tester.runAsync(() async {
      final d = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil', quantity: 1);
      await store.commit(d);
      id = d.id;
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.options));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.edit).last);
    await tester.pumpAndSettle();
    await openSection(tester, s.shoppingList);
    await tester.ensureVisible(find.text(s.autoShopTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.autoShopTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await settleIo(tester);
    expect(store.byId(id)!.autoShop, isTrue);

    await tester.tap(find.byTooltip(s.decrease));
    await settleIo(tester);
    expect(store.shoppingItems.single.id, id);
    expect(find.text('${s.ranOut('Pil')} ${s.nowOnShoppingList}'), findsOneWidget);
  });

  testWidgets('paketli eşyada bir kısmı geçince kartta damga; menüden tarihi geçenler atılır, kalanlar yerinde', (tester) async {
    await boot(tester);
    late String id;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await tester.runAsync(() async {
      final d = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Yoğurt',
            quantity: 5,
            lots: [
              Lot(2, today.subtract(const Duration(days: 2))),
              Lot(3, today.add(const Duration(days: 10))),
            ],
          );
      await store.commit(d);
      id = d.id;
    });
    await tester.pumpAndSettle();
    expect(find.text(s.someExpired(2)), findsOneWidget);
    expect(find.textContaining(s.moreDates(1)), findsOneWidget);

    await tester.tap(find.byTooltip(s.options));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.discardExpiredAction(2)));
    await settleIo(tester);
    expect(store.byId(id)!.quantity, 3);
    expect(store.byId(id)!.lots, isEmpty, reason: 'tek tarih kaldı');
    expect(find.text(s.discardedExpired('Yoğurt', 2)), findsOneWidget);
    expect(find.text(s.someExpired(2)), findsNothing);
  });

  testWidgets('görüntüyle arama kamerayı kendiliğinden açmaz; vazgeçince sayfada kalır', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      // Karşılaştırılacak en az bir fotoğraf olsun.
      final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
            name: 'Matkap',
            imagePath: 'images/matkap.jpg',
          );
      await store.commit(n);
    });
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.searchInventory));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.visualSearch).last);
    await tester.pumpAndSettle();

    // Kamera doğrudan açılmaz: önce ne yapılacağı sorulur.
    expect(find.text(s.visualSearchTake), findsOneWidget);
    expect(find.text(s.visualSearchFromGallery), findsOneWidget);

    // Kamera beklenirken çıkış yolu var: vazgeçmek sayfadan atmaz, seçim
    // ekranına döner (kamera takılıp kalsa da kullanıcı sıkışmaz).
    await tester.tap(find.text(s.visualSearchTake));
    await tester.pump();
    expect(find.text(s.cancel), findsOneWidget);

    await tester.tap(find.text(s.cancel));
    await tester.pump();
    expect(find.text(s.visualSearchTake), findsOneWidget, reason: 'seçim ekranına dönülür');
    expect(find.text(s.visualSearch), findsWidgets, reason: 'sayfa açık kaldı');
  });

  testWidgets('uygulama yeniden açılınca son açık klasörde devam edilir', (tester) async {
    await boot(tester);
    final (kutu, _) = await boxWithBattery(tester, inside: true);
    await tester.tap(find.text('Kutu'));
    await tester.pumpAndSettle();
    expect(store.settings.lastLevel, kutu, reason: 'açık seviye hatırlandı');

    // Uygulama kapanıp açıldı: veriler aynı, arayüz baştan kuruldu.
    await tester.pumpWidget(EnvanterApp(key: UniqueKey(), store: store, sharing: sharing));
    await tester.pumpAndSettle();
    expect(find.text('Pil'), findsOneWidget, reason: 'klasörün içi açık');

    // Geri dönünce ana ekrana çıkılır ve hatırlanan seviye temizlenir.
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text(s.appTitle), findsWidgets);
    expect(store.settings.lastLevel, isNull);
    // Ayar yazımı gerçek zamanda bitsin (testin sahte saatinde beklemez).
    await settleIo(tester);
  });

  testWidgets('klasör bırakılınca sorulur: klasörün kendisi mi, içindekiler mi', (tester) async {
    await boot(tester);
    late String kutu;
    late String depo;
    late String pil;
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      kutu = k.id;
      final d = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Depo');
      await store.commit(d);
      depo = d.id;
      final p = store.draft(parentId: k.id, kind: NodeKind.item).copyWith(name: 'Pil');
      await store.commit(p);
      pil = p.id;
    });
    await tester.pumpAndSettle();

    // Soru sayfası: sürüklemenin kendisi ayrıca sınanıyor, burada seçim önemli.
    final context = tester.element(find.byType(HomeScreen));
    unawaited(NodeActions.dropFolder(
      context,
      folder: store.byId(kutu)!,
      targetId: depo,
    ));
    await tester.pumpAndSettle();
    expect(find.text(s.dropMoveFolder), findsOneWidget);
    expect(find.text(s.dropContentsOnly), findsOneWidget);

    await tester.tap(find.text(s.dropContentsOnly));
    await settleIo(tester);
    await settleIo(tester);
    expect(store.byId(pil)!.parentId, depo, reason: 'içindekiler gitti');
    expect(store.byId(kutu)!.parentId, isNull, reason: 'klasör boş olarak yerinde kaldı');
    expect(store.childCount(kutu), 0);
  });

  testWidgets('sürüklenip klasöre bırakılan kart "Geri al" ile eski yerine ve sırasına döner', (tester) async {
    await boot(tester);
    late String kutu;
    late String pil;
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      kutu = k.id;
      for (final name in ['Bant', 'Pil', 'Makas']) {
        final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name);
        await store.commit(n);
        if (name == 'Pil') pil = n.id;
      }
    });
    await tester.pumpAndSettle();
    expect(store.childrenOf(Roots.home).map((n) => n.name), ['Kutu', 'Bant', 'Pil', 'Makas']);

    final g = await pickUp(tester, 'Pil');
    await g.moveTo(tester.getCenter(find.text('Kutu')));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await settleIo(tester);
    expect(store.byId(pil)!.parentId, kutu);
    expect(find.text(s.movedInto('Pil', 'Kutu')), findsOneWidget);

    await tester.tap(find.text(s.undo));
    await settleIo(tester);
    expect(store.byId(pil)!.parentId, isNull);
    expect(store.childrenOf(Roots.home).map((n) => n.name), ['Kutu', 'Bant', 'Pil', 'Makas'], reason: 'sırası da eski');
  });

  testWidgets('kenardaki çekmece kulbuna bırakılan kart da geri alınır', (tester) async {
    await boot(tester);
    final (_, pil) = await boxWithBattery(tester);
    final g = await pickUp(tester, 'Pil');
    await g.moveTo(tester.getCenter(find.byType(DrawerEdge)));
    await tester.pump(const Duration(milliseconds: 100));
    await g.up();
    await settleIo(tester);
    expect(store.byId(pil)!.inDrawer, isTrue);
    expect(find.text(s.movedToDrawer('Pil')), findsOneWidget);

    await tester.tap(find.text(s.undo));
    await settleIo(tester);
    expect(store.byId(pil)!.inDrawer, isFalse);
    expect(store.childrenOf(Roots.home).map((n) => n.name), ['Kutu', 'Pil']);
  });

  testWidgets('klasörün yalnızca içindekiler aktarılınca "Geri al" hepsini eski klasörüne döndürür', (tester) async {
    await boot(tester);
    late String kutu;
    late String depo;
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      kutu = k.id;
      final d = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Depo');
      await store.commit(d);
      depo = d.id;
      for (final name in ['Pil', 'Bant']) {
        await store.commit(store.draft(parentId: k.id, kind: NodeKind.item).copyWith(name: name));
      }
    });
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(HomeScreen));
    unawaited(NodeActions.dropFolder(context, folder: store.byId(kutu)!, targetId: depo));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.dropContentsOnly));
    await settleIo(tester);
    await settleIo(tester);
    expect(store.childCount(depo), 2);

    await tester.tap(find.text(s.undo));
    await settleIo(tester);
    expect(store.childrenOf(kutu).map((n) => n.name), ['Pil', 'Bant']);
    expect(store.childCount(depo), 0);
  });

  testWidgets('klasörün içine girilip bırakılınca da sorulur', (tester) async {
    await boot(tester);
    late String depo;
    late String kutu;
    late String pil;
    await tester.runAsync(() async {
      final d = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Depo');
      await store.commit(d);
      depo = d.id;
      // Kutu çekmecede: sürüklemeye başlayınca panel çekilir, arkada açık olan
      // seviye (Depo'nun içi) kalır — kullanıcının "içine girip bırakma"sı.
      final k = store.draft(parentId: Roots.drawer, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      kutu = k.id;
      final p = store.draft(parentId: k.id, kind: NodeKind.item).copyWith(name: 'Pil');
      await store.commit(p);
      pil = p.id;
    });
    await tester.pumpAndSettle();

    // Depo'nun içine in.
    await tester.tap(find.text('Depo'));
    await tester.pumpAndSettle();
    expect(find.text(s.upOneLevel), findsNothing, reason: 'sürükleme yokken nokta çıkmaz');

    // Çekmeceyi aç, Kutu'yu al ve bu seviyenin zeminine bırak.
    await tester.tap(find.byTooltip(s.drawer));
    await tester.pumpAndSettle();
    final g = await pickUp(tester, 'Kutu');
    await tester.pump(const Duration(milliseconds: 300));
    // Önce panelden dışarı: çekmece kenara çekilir, altındaki seviye açılır.
    await g.moveTo(const Offset(30, 300));
    await tester.pumpAndSettle();
    await g.moveTo(tester.getCenter(find.byType(NodeListView).last));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();

    expect(find.text(s.dropMoveFolder), findsOneWidget, reason: 'içine girilince de soruluyor');
    expect(find.text(s.dropContentsOnly), findsOneWidget);

    await tester.tap(find.text(s.dropContentsOnly));
    await settleIo(tester);
    await settleIo(tester);
    expect(store.byId(pil)!.parentId, depo, reason: 'içindekiler klasörün içine geçti');
    expect(store.byId(kutu)!.inDrawer, isTrue, reason: 'klasör çekmecede boş kaldı');
    expect(store.childCount(kutu), 0);
  });

  /// Çekmecedeki kartlar önce çekmecenin içinde düzenlenebilmeli: panel
  /// sürükleme başlar başlamaz kapanmamalı.
  testWidgets('çekmecedeki kart sürüklenirken panel açık kalır ve içinde düzenlenir', (tester) async {
    await boot(tester);
    late String kutu;
    late String pil;
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.drawer, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      kutu = k.id;
      final p = store.draft(parentId: Roots.drawer, kind: NodeKind.item).copyWith(name: 'Pil');
      await store.commit(p);
      pil = p.id;
    });
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(s.drawer));
    await tester.pumpAndSettle();
    expect(find.byType(UnsortedDrawerBody), findsOneWidget);

    final g = await pickUp(tester, 'Pil');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(UnsortedDrawerBody), findsOneWidget, reason: 'panel açık kaldı');

    // Çekmecenin içindeki klasöre bırak.
    final box = find.ancestor(of: find.text('Kutu'), matching: find.byType(NodeCardTile)).first;
    await g.moveTo(tester.getCenter(box));
    await tester.pump();
    await g.up();
    await settleIo(tester);
    await settleIo(tester);
    expect(store.byId(pil)!.parentId, kutu, reason: 'çekmecede düzenlendi');
  });

  testWidgets('kart panelin dışına çıkarılınca çekmece kenara çekilir', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      final p = store.draft(parentId: Roots.drawer, kind: NodeKind.item).copyWith(name: 'Pil');
      await store.commit(p);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.drawer));
    await tester.pumpAndSettle();

    final g = await pickUp(tester, 'Pil');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(UnsortedDrawerBody), findsOneWidget);

    // Sola, panelin dışına doğru.
    await g.moveTo(const Offset(30, 300));
    await tester.pumpAndSettle();
    expect(find.byType(UnsortedDrawerBody), findsNothing, reason: 'deste açıldı');

    await g.up();
    await settleIo(tester);
  });

  testWidgets('panel çekildikten sonra kenarda beklenince geri açılır', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      final p = store.draft(parentId: Roots.drawer, kind: NodeKind.item).copyWith(name: 'Pil');
      await store.commit(p);
    });
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(s.drawer));
    await tester.pumpAndSettle();

    final g = await pickUp(tester, 'Pil');
    await tester.pump(const Duration(milliseconds: 400));
    await g.moveTo(const Offset(30, 300));
    await tester.pumpAndSettle();
    expect(find.byType(UnsortedDrawerBody), findsNothing);

    // Kartı geri koymak isteyen kullanıcı kenardaki çekmece hedefinde bekler.
    // Kart zaten çekmecede olduğu için bırakma bir şey değiştirmez; beklemenin
    // işi paneli açmak.
    await g.moveTo(tester.getCenter(find.text(s.drawer)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.byType(UnsortedDrawerBody), findsOneWidget, reason: 'çekmece geri açıldı');

    await g.up();
    await settleIo(tester);
  });

  testWidgets('aramada harf farkı gözetilmez; notta bulunan kaydın not parçası görünür', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Garaj');
      await store.commit(k);
      await store.commit(store.draft(parentId: k.id, kind: NodeKind.item).copyWith(name: 'Çekiç'));
      await store.commit(
        store.draft(parentId: k.id, kind: NodeKind.item).copyWith(name: 'Tornavida', note: 'yıldız uçlu, şarjlı'),
      );
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.searchInventory));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'cekic');
    await tester.pumpAndSettle();
    expect(find.text(s.upper(s.resultCount(1))), findsOneWidget);
    expect(find.text('Çekiç'), findsOneWidget);

    // Adda geçmeyen kelime: neden bulunduğu notun parçasından anlaşılır.
    await tester.enterText(find.byType(TextField), 'SARJLI tornavida');
    await tester.pumpAndSettle();
    expect(find.text('Tornavida'), findsOneWidget);
    expect(find.text('${s.inNote}: yıldız uçlu, şarjlı'), findsOneWidget);
  });

  testWidgets('aramadan kayda gidilince son açık klasör o klasördür; yeniden açılışta oraya dönülür', (tester) async {
    await boot(tester);
    final (kutu, _) = await boxWithBattery(tester, inside: true);
    expect(store.settings.lastLevel, isNull, reason: 'ana ekrandayız');

    await tester.tap(find.text(s.searchInventory));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pil');
    await tester.pumpAndSettle();
    // "Yerine git": arama kapanır, kaydın klasörü açılır.
    await tester.tap(find.byTooltip(s.goToPlace));
    await settleIo(tester);
    expect(find.byType(SearchPage), findsNothing);
    expect(find.widgetWithText(NodeCard, 'Pil'), findsOneWidget);
    expect(store.settings.lastLevel, kutu, reason: 'ekranda Kutu açık');

    // Geri dönünce yine ana ekran hatırlanır.
    await tester.binding.handlePopRoute();
    await settleIo(tester);
    expect(store.settings.lastLevel, isNull);
  });

  testWidgets('sonuçsuz aramada ne deneneceği yazar; QR ve fotoğrafla arama bir dokunuş ötede', (tester) async {
    await boot(tester);
    await boxWithBattery(tester);
    await tester.tap(find.text(s.searchInventory));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'matkap');
    await tester.pumpAndSettle();
    expect(find.text(s.noResultFor('matkap')), findsOneWidget);
    expect(find.text(s.noResultHint), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, s.scanQr), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, s.visualSearch));
    await tester.pumpAndSettle();
    expect(find.byType(VisualSearchPage), findsOneWidget);
  });

  testWidgets('boş çöp kutusu ne işe yaradığını söyler', (tester) async {
    await boot(tester);
    unawaited(Navigator.of(tester.element(find.byType(HomeScreen)))
        .push(MaterialPageRoute<void>(builder: (_) => const TrashPage())));
    await tester.pumpAndSettle();
    expect(find.text(s.trashEmpty), findsOneWidget);
    expect(find.text(s.trashEmptyHint), findsOneWidget);
  });

  testWidgets('çöpteki kayıt 30 gün bekletmeden tamamen silinir; "Son silinenler" de temizlenir', (tester) async {
    await boot(tester);
    final ids = <String, String>{};
    await tester.runAsync(() async {
      for (final name in ['Lamba', 'Masa']) {
        final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name);
        await store.commit(n);
        await store.moveToTrash(n.id);
        ids[name] = n.id;
      }
    });
    await tester.pumpAndSettle();
    unawaited(Navigator.of(tester.element(find.byType(HomeScreen)))
        .push(MaterialPageRoute<void>(builder: (_) => const TrashPage())));
    await tester.pumpAndSettle();

    // Kutuyu işaretleyince: "Son silinenler"e girmez, düğme "Tamamen sil" olur.
    Future<void> deleteFromTrash(String name, {required bool now}) async {
      final tile = find.widgetWithText(RecordTile, name);
      await tester.tap(find.descendant(of: tile, matching: find.byTooltip(s.deleteForever)));
      await tester.pumpAndSettle();
      expect(find.text(s.deleteNowOption), findsOneWidget);
      if (now) {
        await tester.tap(find.text(s.deleteNowOption));
        await tester.pumpAndSettle();
        expect(find.text(s.deleteNowWarning), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, s.deleteNow));
      } else {
        await tester.tap(find.widgetWithText(FilledButton, s.delete));
      }
      await settleIo(tester);
    }

    await deleteFromTrash('Lamba', now: true);
    expect(store.byId(ids['Lamba']!), isNull);
    expect(store.recentlyPurged, isEmpty);
    expect(find.text(s.recentlyPurged), findsNothing);

    // Bekletilerek silinen "Son silinenler"de durur; oradan da beklemeden temizlenir.
    await deleteFromTrash('Masa', now: false);
    expect(store.recentlyPurged.single.node.id, ids['Masa']);
    expect(find.text(s.recentlyPurged), findsOneWidget);
    await tester.tap(find.text(s.clearPurged));
    await tester.pumpAndSettle();
    expect(find.text(s.clearPurgedWarning(1)), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, s.deleteNow));
    await settleIo(tester);
    expect(store.recentlyPurged, isEmpty);
    expect(find.text(s.trashEmpty), findsOneWidget);
  });

  testWidgets('boş aramada son dokunulan kayıtlar, en yenisi üstte', (tester) async {
    await boot(tester);
    await boxWithBattery(tester, inside: true);
    await tester.tap(find.text(s.searchInventory));
    await tester.pumpAndSettle();

    expect(find.text(s.upper(s.recentTitle)), findsOneWidget);
    expect(tester.getTopLeft(find.text('Pil')).dy, lessThan(tester.getTopLeft(find.text('Kutu')).dy));
    expect(find.text('${s.home} / Kutu'), findsOneWidget, reason: 'nerede durduğu alt yazıda');
  });

  /// Kartın ⋯ düğmesinden "Seç".
  Future<void> startSelecting(WidgetTester tester, String card) async {
    await tester.tap(find.descendant(of: find.widgetWithText(NodeCard, card), matching: find.byTooltip(s.options)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.select));
    await tester.pumpAndSettle();
  }

  testWidgets('toplu seçim: seçilenler birlikte çöpe gider, geri alınınca döner', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      for (final name in ['Pil', 'Tel', 'Makas']) {
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name));
      }
    });
    await tester.pumpAndSettle();
    String id(String name) => store.childrenOf(Roots.home).firstWhere((n) => n.name == name).id;
    final pil = id('Pil'), tel = id('Tel'), makas = id('Makas');

    await startSelecting(tester, 'Pil');
    expect(find.text(s.selectedCount(1)), findsOneWidget);
    expect(find.byTooltip(s.options), findsNothing, reason: 'seçerken kartın ⋯ düğmesi yok');

    // Karta dokunmak artık açmaz, seçer; ikinci dokunuş seçimi kaldırır.
    await tester.tap(find.text('Tel'));
    await tester.pumpAndSettle();
    expect(find.text(s.selectedCount(2)), findsOneWidget);
    await tester.tap(find.text('Pil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pil'));
    await tester.pumpAndSettle();
    expect(find.text(s.selectedCount(2)), findsOneWidget);

    await tester.tap(find.text(s.trashShort));
    await settleIo(tester);
    expect(store.byId(pil)!.isDeleted, isTrue);
    expect(store.byId(tel)!.isDeleted, isTrue);
    expect(store.byId(makas)!.isDeleted, isFalse);
    expect(find.text(s.trashedMany(2)), findsOneWidget);
    expect(find.text(s.searchInventory), findsOneWidget, reason: 'seçim bitti, alt çubuk döndü');

    await tester.tap(find.text(s.undo));
    await settleIo(tester);
    expect(store.byId(pil)!.isDeleted, isFalse);
    expect(store.byId(tel)!.isDeleted, isFalse);
  });

  testWidgets('toplu seçim: "Tümünü seç" ve "Taşı" ile hepsi bir klasöre gider', (tester) async {
    await boot(tester);
    late String kutu;
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      kutu = k.id;
      for (final name in ['Pil', 'Tel']) {
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name));
      }
    });
    await tester.pumpAndSettle();

    await startSelecting(tester, 'Pil');
    await tester.tap(find.byTooltip(s.selectAll));
    await tester.pumpAndSettle();
    expect(find.text(s.selectedCount(3)), findsOneWidget);
    // Kutu da seçili: kendi içine gidemez, seçimden çıkarılır.
    await tester.tap(find.text('Kutu'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.moveShort));
    await tester.pumpAndSettle();
    expect(find.text(s.whereShouldGoMany(2)), findsOneWidget);
    // Seçici kayıtların durduğu yerde açılır; Kutu'ya girilir, "Buraya taşı".
    expect(find.text(s.alreadyHere), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Kutu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.moveHere));
    await settleIo(tester);

    expect(store.childrenOf(kutu).map((n) => n.name), ['Pil', 'Tel']);
    expect(find.text(s.movedMany(2, '${s.home} / Kutu')), findsOneWidget);
  });

  testWidgets('yer seçici klasörün içinde açılır; ↑ ile üst klasöre çıkılıp oraya taşınır', (tester) async {
    await boot(tester);
    late String garaj;
    await tester.runAsync(() async {
      Future<String> add(String parent, NodeKind kind, String name) async {
        final n = store.draft(parentId: parent, kind: kind).copyWith(name: name);
        await store.commit(n);
        return n.id;
      }

      garaj = await add(Roots.home, NodeKind.container, 'Garaj');
      final raf = await add(garaj, NodeKind.container, 'Raf');
      final goz = await add(raf, NodeKind.container, 'Alt göz');
      await add(goz, NodeKind.item, 'Pil');
      await add(goz, NodeKind.item, 'Tel');
      await add(Roots.home, NodeKind.container, 'Mutfak');
    });
    await tester.pumpAndSettle();
    for (final folder in ['Garaj', 'Raf', 'Alt göz']) {
      await tester.tap(find.text(folder).last);
      await tester.pumpAndSettle();
    }

    await startSelecting(tester, 'Pil');
    await tester.tap(find.byTooltip(s.selectAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.moveShort));
    await tester.pumpAndSettle();

    // Kayıtların durduğu klasörde açılır: burada alt klasör yok, buraya taşımak anlamsız.
    expect(find.text(s.noFoldersHere), findsOneWidget);
    expect(find.text(s.alreadyHere), findsOneWidget);

    // ↑: Raf. Alt göz "şu anki yeri" olarak listede.
    await tester.tap(find.byTooltip(s.upOneLevel));
    await tester.pumpAndSettle();
    expect(find.text(s.currentPlace), findsOneWidget);
    expect(find.text(s.moveHere), findsOneWidget);

    // Yolun başına dokunmak ana ekrana çıkarır; oradan Garaj'a girilir.
    await tester.tap(find.text(s.home).last);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Mutfak'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Garaj'));
    await tester.pumpAndSettle();
    expect(find.text(s.folderCount(1)), findsOneWidget, reason: 'Raf\'ın içinde bir klasör var');

    await tester.tap(find.text(s.moveHere));
    await settleIo(tester);
    expect(store.childrenOf(garaj).map((n) => n.name), ['Raf', 'Pil', 'Tel']);
    expect(find.text(s.movedMany(2, '${s.home} / Garaj')), findsOneWidget);
  });

  testWidgets('sol menü açıkken geri tuşu menüyü kapatır, uygulamadan çıkarmaz', (tester) async {
    // Android'in öngörülü geri hareketinde sistem, Flutter "geriyi ben karşılarım"
    // demedikçe etkinliği kendisi kapatır. Uygulamanın ne dediği bu kanaldan izlenir.
    final handles = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.setFrameworkHandlesBack') handles.add(call.arguments as bool);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    // Uygulama öndeyken bildirilir (testte yaşam döngüsü kendiliğinden gelmez).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await boot(tester);
    expect(handles.lastOrNull ?? false, isFalse, reason: 'ana ekranda geri uygulamadan çıkarır: sistem karşılar');

    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    expect(find.byType(LeftDrawer), findsOneWidget);
    expect(handles.last, isTrue, reason: 'menü açıkken geriyi uygulama karşılar');

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byType(LeftDrawer), findsNothing);
    expect(find.text(s.appTitle), findsOneWidget);
    expect(handles.last, isFalse, reason: 'menü kapandı: geri yine sistemin');

    // Kenara dokunarak kapatılınca da durum güncellenir.
    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    expect(handles.last, isTrue);
    await tester.tapAt(const Offset(400, 430));
    await tester.pumpAndSettle();
    expect(find.byType(LeftDrawer), findsNothing);
    expect(handles.last, isFalse);
  });

  testWidgets('geri tuşu seçimi bitirir, uygulamadan çıkmaz', (tester) async {
    await boot(tester);
    await boxWithBattery(tester);
    await startSelecting(tester, 'Pil');
    expect(find.text(s.selectedCount(1)), findsOneWidget);
    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.text(s.selectedCount(1)), findsNothing);
    expect(find.text(s.appTitle), findsOneWidget);
  });

  testWidgets('yedek zamanı gelince menüde hatırlatılır; "Sonra" susturur', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      // On gün önce başlanmış, hiç yedeklenmemiş bir envanter.
      final old = DateTime.now().subtract(const Duration(days: 10));
      for (var i = 0; i < 6; i++) {
        await store.commit(Node(
          id: 'eski-$i',
          parentId: null,
          kind: NodeKind.container,
          name: 'Kutu $i',
          color: 0xFFE0C9A6,
          sortIndex: i.toDouble(),
          createdAt: old,
          updatedAt: old,
        ));
      }
    });
    await tester.pumpAndSettle();
    expect(store.backupDue, isTrue);

    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    expect(find.text(s.backupReminderTitle), findsOneWidget);
    expect(find.text(s.backupNow), findsOneWidget);

    await tester.tap(find.text(s.later));
    await settleIo(tester);
    expect(find.text(s.backupReminderTitle), findsNothing);
    expect(store.settings.backupSnoozedAt, isNotNull);
  });

  testWidgets('Ayarlar\'da dışa aktarmanın altında son yedek yazar', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip(s.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, s.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.settingsInventory));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(s.neverBackedUp), 300);
    expect(find.text(s.neverBackedUp), findsOneWidget);

    await tester.runAsync(() => store.markBackedUp());
    await tester.pumpAndSettle();
    expect(find.text(s.lastBackup(s.today)), findsOneWidget);
    await settleIo(tester);
  });

  testWidgets('Ayarlar iki sekme: bana ait olanlar ve bu envanterin ayarları; son sekme hatırlanır', (tester) async {
    await boot(tester);
    Future<void> openSettings() async {
      await tester.tap(find.byTooltip(s.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, s.settings));
      await tester.pumpAndSettle();
    }

    await openSettings();
    await tester.tap(find.text(s.settingsMine));
    await tester.pumpAndSettle();
    // Bana ait: görünüm, dil, otomatik yedek. Envanterinkiler yok.
    expect(find.text(s.upper(s.appearance)), findsOneWidget);
    expect(find.text(s.upper(s.language)), findsOneWidget);
    expect(find.text(s.autoBackupTitle), findsOneWidget);
    expect(find.text(s.groupKindsTitle), findsNothing);
    expect(find.text(s.exportTitle), findsNothing);

    await tester.tap(find.text(s.settingsInventory));
    await tester.pumpAndSettle();
    // Bu envanter: deste ayarları hemen görünür; görünüm ve dil yok.
    expect(find.text(s.groupKindsTitle), findsOneWidget);
    expect(find.text(s.upper(s.language)), findsNothing);
    await tester.scrollUntilVisible(find.text(s.exportTitle), 300);
    expect(find.text(s.importTitle), findsOneWidget);
    // Sekmeler kaydırınca da yerinde durur.
    expect(find.text(s.settingsMine), findsOneWidget);

    // Çıkıp yeniden girince aynı sekme.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await openSettings();
    expect(find.text(s.groupKindsTitle), findsOneWidget);
    await tester.tap(find.text(s.settingsMine));
    await tester.pumpAndSettle();
  });

  testWidgets('klasörün ⋮ menüsünden QR etiket sayfası: klasörler ya da hepsi', (tester) async {
    await boot(tester);
    await tester.runAsync(() async {
      final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
      await store.commit(k);
      await store.commit(store.draft(parentId: k.id, kind: NodeKind.container).copyWith(name: 'Raf'));
      await store.commit(store.draft(parentId: k.id, kind: NodeKind.item).copyWith(name: 'Pil'));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kutu'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(s.moreActions));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.qrLabels));
    await tester.pumpAndSettle();
    expect(find.text(s.labelsTitle), findsOneWidget);
    expect(find.text(s.labelCount(2, 1)), findsOneWidget, reason: 'kutu ve rafı');

    await tester.tap(find.text(s.labelScopeAll));
    await tester.pumpAndSettle();
    expect(find.text(s.labelCount(3, 1)), findsOneWidget, reason: 'pil de');
  });

  // Telefonun yazı boyutu ve ekran boyutu en büyüğe alınmış (az görenlerin
  // ayarı): sabit boydaki yüzeyler (başlık, kart, satır, ek şeridi) taşmamalı.
  // Taşma olursa test kendiliğinden düşer (RenderFlex overflow bir hatadır).
  for (final (scale, width) in [(1.3, 320.0), (2.0, 320.0), (2.0, 360.0)]) {
    testWidgets('yazı $scale kat, ekran ${width.round()} dp: kart, satır, başlık ve ek şeridi taşmaz', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await boot(tester, size: Size(width, 780));
      late String matkap;
      await tester.runAsync(() async {
        final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Mutfak dolabı üst raf', isFull: true);
        await store.commit(k);
        final m = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
              name: 'Darbeli şarjlı matkap seti',
              quantity: 12,
              minQuantity: 20,
              note: 'Garajdaki rafta, çantasının içinde',
              expiresAt: DateTime(2020, 1, 1),
              wantedAt: DateTime(2026, 9, 1),
              attachments: [Attachment(id: 'a', name: 'Kullanım kılavuzu', addedAt: DateTime(2026), url: 'https://ornek.com/k')],
            );
        await store.commit(m);
        matkap = m.id;
        await store.toggleFavorite(m.id);
      });
      await tester.pumpAndSettle();
      expect(find.widgetWithText(NodeCard, 'Darbeli şarjlı matkap seti'), findsOneWidget);

      // Odak görünümü (ek şeridiyle) ve düzenleyici.
      await tester.tap(find.text('Darbeli şarjlı matkap seti'));
      await tester.pumpAndSettle();
      expect(find.text('Kullanım kılavuzu'), findsOneWidget);
      await tester.tap(find.text(s.edit).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.cancel));
      await tester.pumpAndSettle();

      // Liste görünümü.
      await tester.runAsync(() => store.updateSettings(store.settings.copyWith(listView: true)));
      await tester.pumpAndSettle();
      expect(find.byType(NodeRow), findsNWidgets(2));

      // Alışveriş listesi satırı (✋ ✕ "Aldım" düğmeleriyle).
      unawaited(Navigator.of(tester.element(find.byType(HomeScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const ShoppingPage())));
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingPage), findsOneWidget);
      expect(store.byId(matkap)!.isWanted, isTrue);
    });
  }

  group('"bugün" şeridi', () {
    testWidgets('boş envanterde şerit yok; ilgi isteyenler etiket olarak çıkar, dokununca yeri açılır', (tester) async {
      await boot(tester);
      expect(find.byType(TodayStrip), findsOneWidget);
      expect(tester.getSize(find.byType(TodayStrip)).height, 0, reason: 'gösterecek bir şey yokken yer kaplamaz');

      late String kayip;
      await tester.runAsync(() async {
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil'));
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item)
            .copyWith(name: 'Süt', quantity: 1, expiresAt: DateTime(2020, 1, 1), wantedAt: DateTime(2026, 9, 1)));
        // Bir yıl önce alınmış, on gün sonra bitiyor: genel uyarı süresinin (3 ay) içinde.
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
              name: 'Yoğurt',
              quantity: 1,
              purchasedAt: DateTime.now().subtract(const Duration(days: 365)),
              expiresAt: DateTime.now().add(const Duration(days: 10)),
            ));
        await store.commit(store.draft(parentId: Roots.drawer, kind: NodeKind.item).copyWith(name: 'Kablo'));
        final k = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Makas');
        await store.commit(k);
        kayip = k.id;
        await store.markLost(kayip);
      });
      await tester.pumpAndSettle();
      // Şerit yana kayar (test yazı tipi geniş: etiketlerin hepsi aynı anda sığmaz).
      final strip = find.descendant(of: find.byType(TodayStrip), matching: find.byType(Scrollable));
      Future<void> see(String label, {double step = 120}) async {
        await tester.scrollUntilVisible(find.text(label), step, scrollable: strip);
        // Kenarda yarım kalmasın: dokunuş etiketin ortasına gitsin.
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
      }
      for (final label in [s.todayExpired(1), s.todaySoon(1), s.todayToBuy(1), s.todayLost(1), s.todayInDrawer(1)]) {
        await see(label);
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text(s.todayToPutAway(1)), findsNothing, reason: 'sıfır olan görünmez');
      // Şerit kartların üstünde.
      expect(
        tester.getRect(find.byType(TodayStrip)).bottom,
        lessThanOrEqualTo(tester.getRect(find.widgetWithText(NodeCard, 'Pil')).top),
      );

      await see(s.todayToBuy(1));
      await tester.tap(find.text(s.todayToBuy(1)));
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      await see(s.todayExpired(1), step: -120);
      await tester.tap(find.text(s.todayExpired(1)));
      await tester.pumpAndSettle();
      expect(find.text(s.datesPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Kayıp etiketi kayıp çekmecesini açar.
      await see(s.todayLost(1));
      await tester.tap(find.text(s.todayLost(1)));
      await tester.pumpAndSettle();
      expect(find.text('Makas'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Klasörün içinde şerit yok (yalnızca ana ekranda).
      await tester.runAsync(
        () => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Dolap')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dolap'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayStrip).hitTestable(), findsNothing);
    });
  });

  group('deste kaydırılırken', () {
    testWidgets('kartlar yeniden kurulmaz; üst bileşen yenilenince kurulur; ekrandan çıkan saklanmaz', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final built = <int, int>{};
      var label = 'kart';
      late StateSetter refresh;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(builder: (context, setState) {
            refresh = setState;
            return StackedCardList(
              controller: scroll,
              itemCount: 60,
              itemBuilder: (context, i, focus) {
                built[i] = (built[i] ?? 0) + 1;
                return Text('$label $i');
              },
            );
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(built[0], 1);
      final onScreen = built.length;
      expect(onScreen, lessThan(20), reason: 'yalnızca görünenler kurulur');

      // Kaydırma: görünmeye devam eden kart bir daha kurulmaz, yeni giren bir kez kurulur.
      for (var i = 0; i < 12; i++) {
        scroll.jumpTo(scroll.offset + 20);
        await tester.pump();
      }
      expect(built[2], 1, reason: 'kaydırma kartı baştan kurdurmaz');
      expect(built.values.every((n) => n == 1), isTrue);
      expect(built.length, greaterThan(onScreen), reason: 'aşağıdan yeni kartlar girdi');

      // İçerik değişti (üst bileşen yeniden kuruldu): görünen kartlar yenilenir.
      refresh(() => label = 'yeni');
      await tester.pump();
      expect(find.text('yeni 3'), findsOneWidget);
      expect(find.textContaining('kart '), findsNothing);

      // Ekrandan çıkan saklanmaz: geri gelince yeniden kurulur.
      final before = built[0]!;
      scroll.jumpTo(3000);
      await tester.pump();
      expect(find.text('yeni 0'), findsNothing);
      scroll.jumpTo(0);
      await tester.pump();
      expect(find.text('yeni 0'), findsOneWidget);
      expect(built[0], before + 1);
    });

    testWidgets('odak karta dinlenen bir değer olarak gider: kaydırdıkça değişir, liste düzeninde hep 1', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final focus = <int, ValueListenable<double>>{};
      final repaints = <int, int>{};
      Widget deck({required bool flat}) => MaterialApp(
            home: Scaffold(
              body: StackedCardList(
                controller: scroll,
                itemCount: 30,
                peek: 100,
                flat: flat,
                itemBuilder: (context, i, f) {
                  focus[i] = f;
                  return FocusBuilder(
                    focus: f,
                    builder: (context, value, _) {
                      repaints[i] = (repaints[i] ?? 0) + 1;
                      return Text('$i');
                    },
                  );
                },
              ),
            ),
          );
      await tester.pumpWidget(deck(flat: false));
      await tester.pumpAndSettle();
      expect(focus[0]!.value, 1.0);
      expect(focus[1]!.value, 0.0);
      expect(focus[4]!.value, 0.0);

      scroll.jumpTo(50);
      await tester.pump();
      expect(focus[0]!.value, closeTo(0.5, 0.001));
      expect(focus[1]!.value, closeTo(0.5, 0.001));
      scroll.jumpTo(100);
      await tester.pump();
      expect(focus[1]!.value, 1.0);
      // Odağı hiç değişmeyen kartın odağa bağlı parçası da yenilenmez.
      expect(repaints[4], 1);
      expect(repaints[1], greaterThan(1));

      scroll.jumpTo(0);
      await tester.pumpWidget(deck(flat: true));
      await tester.pumpAndSettle();
      scroll.jumpTo(140);
      await tester.pump();
      expect(focus[3]!.value, 1.0, reason: 'düz listede odak kavramı yok');
    });

    testWidgets('gerçek destede: odaktaki kartın alt satırı belirgin, kaydırınca sıradakine geçer; kayıt değişince kart yenilenir', (tester) async {
      await boot(tester);
      late String ikinci;
      await tester.runAsync(() async {
        for (var i = 1; i <= 8; i++) {
          final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Eşya $i', quantity: i);
          if (i == 2) ikinci = n.id;
          await store.commit(n);
        }
      });
      await tester.pumpAndSettle();
      // Kartın alt satırının saydamlığı (odakta 1, destede 0,35).
      double bottom(String name) {
        final card = find.widgetWithText(NodeCard, name);
        final opacity = find.descendant(of: find.descendant(of: card, matching: find.byType(FocusBuilder)), matching: find.byType(Opacity));
        return tester.widget<Opacity>(opacity.last).opacity;
      }

      expect(bottom('Eşya 1'), 1.0);
      expect(bottom('Eşya 2'), closeTo(0.35, 0.001));

      final position = tester
          .state<ScrollableState>(find.descendant(of: find.byType(NodeListView), matching: find.byType(Scrollable)).first)
          .position;
      final peek = tester.widget<StackedCardList>(find.byType(StackedCardList)).peek;
      position.jumpTo(peek);
      await tester.pump();
      expect(bottom('Eşya 2'), 1.0, reason: 'odak kaydırmayla sıradaki karta geçti');
      expect(bottom('Eşya 3'), closeTo(0.35, 0.001));

      // Kaydırılmış haldeyken kayıt değişir: saklanan kart değil, yenisi görünür.
      await tester.runAsync(() => store.commit(store.byId(ikinci)!.copyWith(name: 'Yeni ad', quantity: 41)));
      await tester.pumpAndSettle();
      expect(find.text('Yeni ad'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      expect(find.text('Eşya 2'), findsNothing);
      expect(bottom('Yeni ad'), 1.0);
    });
  });

  group('hareket', () {
    /// Bir [Entrance]'ın o anki saydamlığı, kayması ve ölçeği (dururken 1, sıfır ve 1).
    double opacityOf(WidgetTester tester, Finder entrance) =>
        tester.widget<FadeTransition>(find.descendant(of: entrance, matching: find.byType(FadeTransition)).first).opacity.value;
    Transform moveOf(WidgetTester tester, Finder entrance) =>
        tester.widget<Transform>(find.descendant(of: entrance, matching: find.byType(Transform)).first);
    Offset shiftOf(WidgetTester tester, Finder entrance) {
      final t = moveOf(tester, entrance).transform.getTranslation();
      return Offset(t.x, t.y);
    }

    double scaleOf(WidgetTester tester, Finder entrance) => moveOf(tester, entrance).transform.getMaxScaleOnAxis();
    // Destenin çevresindeki (seviye değişimi) ve içindeki (görünüm/sıra) sarmalayıcılar.
    Finder levelEntrance() => find.ancestor(of: find.byType(NodeListView).last, matching: find.byType(Entrance)).first;
    Finder viewEntrance() => find.descendant(of: find.byType(NodeListView).last, matching: find.byType(Entrance)).first;

    testWidgets('sürüklerken seviye hareketsiz değişir; geri dönerken deste kayarak belirir', (tester) async {
      await boot(tester);
      final (kutu, pil) = await boxWithBattery(tester, inside: true);
      await tester.tap(find.text('Kutu'));
      await tester.pumpAndSettle();

      // Sürüklerken bir üst seviyeye çık: yeni deste hemen, hareketsiz yerinde.
      final g = await pickUp(tester, 'Pil');
      await g.moveTo(tester.getCenter(find.text(s.upOneLevel)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();
      expect(find.text(s.upOneLevel), findsNothing, reason: 'seviye değişti');
      expect(shiftOf(tester, levelEntrance()), Offset.zero, reason: 'parmağın altındaki hedefler kıpırdamaz');
      await tester.pump(const Duration(milliseconds: 60));
      expect(shiftOf(tester, levelEntrance()), Offset.zero);
      await g.moveTo(tester.getCenter(find.text(s.cancelDrag)));
      await tester.pump();
      await g.up();
      await settleIo(tester);
      expect(store.byId(pil)!.parentId, kutu);

      // Sürükleme bitti; geri dönüş (yerinde) hareketli.
      await tester.tap(find.byTooltip(s.back));
      await tester.pump();
      expect(shiftOf(tester, levelEntrance()).dx, lessThan(-15), reason: 'yukarı çıkılınca deste soldan gelir');
      expect(opacityOf(tester, levelEntrance()), 1.0, reason: 'deste solmaz: boş kare görünmesin');
      expect(find.text('Pil'), findsOneWidget, reason: 'içerik hemen yerinde (eski deste beklemez)');
      await tester.pump(const Duration(milliseconds: 100));
      expect(shiftOf(tester, levelEntrance()).dx, inExclusiveRange(-15, 0));
      await tester.pumpAndSettle();
      expect(shiftOf(tester, levelEntrance()), Offset.zero);
    });

    testWidgets('görünüm değişince deste belirir; "animasyonları kaldır" açıkken hareketsiz', (tester) async {
      await boot(tester);
      await boxWithBattery(tester);
      expect(shiftOf(tester, viewEntrance()), Offset.zero, reason: 'ilk çizimde hareket yok');

      await pickView(tester, s.viewList);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      expect(find.byType(NodeRow), findsWidgets);
      expect(shiftOf(tester, viewEntrance()).dy, greaterThan(10), reason: 'yeni düzen aşağıdan gelir');
      expect(opacityOf(tester, viewEntrance()), 1.0);
      await tester.pumpAndSettle();
      expect(shiftOf(tester, viewEntrance()), Offset.zero);

      // Telefonda animasyonlar kapalıysa içerik doğrudan değişir.
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpAndSettle();
      await pickView(tester, s.viewDeck);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      expect(find.byType(NodeCard), findsWidgets);
      expect(shiftOf(tester, viewEntrance()), Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('adet değişince sayı kısa bir an büyür, sonra yerine oturur', (tester) async {
      await boot(tester);
      await tester.runAsync(
        () => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil', quantity: 4)),
      );
      await tester.pumpAndSettle();
      final number = find.descendant(of: find.widgetWithText(NodeCard, 'Pil'), matching: find.byType(Entrance));
      expect(scaleOf(tester, number), closeTo(1.0, 0.001));

      await tester.tap(find.byTooltip(s.increase));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
      expect(scaleOf(tester, number), greaterThan(1.2));
      expect(opacityOf(tester, number), 1.0, reason: 'sayı solmaz, yalnızca kıpırdar');
      await tester.pump(const Duration(milliseconds: 400));
      expect(scaleOf(tester, number), closeTo(1.0, 0.001));
      await settleIo(tester);
    });
  });

  group('klasör kapağı', () {
    /// Klasörün içine fotoğraflı eşya. runAsync içinde çağrılır.
    Future<void> photoInside(String folderId, String name) async {
      await addPhotoItem(name);
      final item = store.childrenOf(Roots.home).firstWhere((n) => n.name == name);
      await store.move(item.id, folderId);
    }

    testWidgets('fotoğrafı olmayan klasörün kartında içindekilerin fotoğrafları durur; kendi fotoğrafı olunca kalkar', (tester) async {
      await boot(tester);
      late String dolap;
      await tester.runAsync(() async {
        final d = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Dolap');
        dolap = d.id;
        await store.commit(d);
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Boş kutu'));
      });
      await tester.pumpAndSettle();
      expect(find.byType(FolderCover), findsNothing, reason: 'içinde fotoğraf yok: kart bugünkü gibi');

      await tester.runAsync(() async {
        await photoInside(dolap, 'Matkap');
        await photoInside(dolap, 'Testere');
      });
      await tester.pumpAndSettle();
      final card = find.widgetWithText(NodeCard, 'Dolap');
      final cover = find.descendant(of: card, matching: find.byType(FolderCover));
      expect(cover, findsOneWidget);
      expect(find.descendant(of: cover, matching: find.byType(Image)), findsNWidgets(2));
      expect(find.byType(FolderCover), findsOneWidget, reason: 'boş klasörde kapak yok');
      // Kapak kartın içinde, sağda; ad ve ⋯ açıkta.
      final cardBox = tester.getRect(card);
      final coverBox = tester.getRect(cover);
      expect(coverBox.left, greaterThan(cardBox.center.dx - 40));
      expect(coverBox.right, lessThan(cardBox.right));
      expect(coverBox.top, greaterThan(tester.getRect(find.descendant(of: card, matching: find.text('Dolap'))).top));

      // Kapak dokunuş almaz: kartın kendisi alır (klasöre girilir, fotoğraf açılmaz).
      final shield = find.ancestor(of: cover, matching: find.byType(IgnorePointer)).first;
      expect(tester.widget<IgnorePointer>(shield).ignoring, isTrue);

      // Klasörün kendi fotoğrafı olunca kapak onundur.
      await tester.runAsync(() async {
        File(AppPaths.abs('images/Matkap.png')).copySync(AppPaths.abs('images/dolap.png'));
        AppPaths.forget('images/dolap.png');
        await store.commit(store.byId(dolap)!.copyWith(imagePath: 'images/dolap.png'));
      });
      await tester.pumpAndSettle();
      expect(find.byType(FolderCover), findsNothing);
      expect(find.descendant(of: card, matching: find.byType(PinnedPhoto)), findsOneWidget);
    });

    testWidgets('listede klasör satırının başında küçük ızgara: fotoğraflar ve klasörün simgesi', (tester) async {
      await boot(tester);
      late String dolap;
      await tester.runAsync(() async {
        final d = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Dolap');
        dolap = d.id;
        await store.commit(d);
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Boş kutu'));
        await photoInside(dolap, 'Matkap');
      });
      await tester.pumpAndSettle();
      await pickView(tester, s.viewList);
      await settleIo(tester);
      final row = find.widgetWithText(NodeRow, 'Dolap');
      final mosaic = find.descendant(of: row, matching: find.byType(FolderMosaic));
      expect(mosaic, findsOneWidget);
      expect(find.byType(FolderMosaic), findsOneWidget, reason: 'boş klasörde simge olduğu gibi');
      expect(find.descendant(of: mosaic, matching: find.byType(Image)), findsOneWidget);
      expect(find.descendant(of: mosaic, matching: find.byType(Icon)), findsOneWidget, reason: 'klasörün simgesi yerinde');
      expect(tester.getSize(mosaic), const Size(42, 42));
      expect(tester.getRect(row).height, NodeRow.height);
    });
  });

  group('ızgara görünümü', () {
    Future<void> grid(WidgetTester tester) async {
      await tester.runAsync(() => store.updateSettings(store.settings.copyWith(deckView: DeckView.grid)));
      await tester.pumpAndSettle();
    }

    testWidgets('düğme sırayla dolaşır; ızgarada kayıtlar yan yana karelerde, ekrana daha çok kayıt sığar; seçim hatırlanır', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu'));
        for (var i = 1; i <= 9; i++) {
          await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Eşya $i'));
        }
      });
      await tester.pumpAndSettle();
      final cardsShown = find.byType(NodeCard).evaluate().length;

      // Düğme sırayla dolaşır; ipucu ve simge sıradaki görünümü söyler.
      expect(find.byTooltip(s.showAs(s.viewList)), findsOneWidget);
      expect(find.descendant(of: find.byType(ViewModeButton), matching: find.byIcon(viewIcon(DeckView.list))), findsOneWidget);
      await tester.tap(find.byType(ViewModeButton));
      await settleIo(tester);
      expect(store.settings.deckView, DeckView.list);
      expect(find.byTooltip(s.showAs(s.viewGrid)), findsOneWidget);
      await tester.tap(find.byType(ViewModeButton));
      await settleIo(tester);
      expect(store.settings.deckView, DeckView.grid);
      expect(find.byTooltip(s.showAs(s.viewDeck)), findsOneWidget, reason: 'ızgaradan sonra yine deste');
      expect(find.byType(PopupMenuItem<DeckView>), findsNothing, reason: 'menü açılmaz: tek dokunuş');
      expect(find.byType(NodeCard), findsNothing);
      expect(find.byType(NodeRow), findsNothing);
      expect(find.byType(NodeTile).evaluate().length, greaterThan(cardsShown), reason: 'aynı ekranda daha çok kayıt');

      // 411 dp'de üç sütun: 1-2-3 yan yana, 4 bir alt satırda 1'in altında.
      Rect at(String name) => tester.getRect(find.widgetWithText(NodeTile, name));
      expect(at('Eşya 2').top, at('Eşya 1').top);
      expect(at('Eşya 2').left, greaterThan(at('Eşya 1').right));
      expect(at('Eşya 3').left, greaterThan(at('Eşya 2').right));
      expect(at('Eşya 4').left, at('Eşya 1').left);
      expect(at('Eşya 4').top, greaterThan(at('Eşya 1').bottom));
      // Kare fotoğraf alanı + ad şeridi; sağdaki kulpların altına girmez.
      expect(at('Eşya 1').height, closeTo(at('Eşya 1').width + NodeTile.labelHeight, 1));
      expect(at('Eşya 3').right, lessThan(411 - 22 - 6 + 0.01));
      expect(find.text(s.items), findsOneWidget, reason: 'klasör/eşya grupları ızgarada da ayrı');

      // Ayar veritabanında: yeniden açılınca ızgara gelir (eski "liste" değeri de okunur).
      late AppSettings reloaded;
      await tester.runAsync(() async => reloaded = await AppSettings.load());
      expect(reloaded.deckView, DeckView.grid);
      await tester.runAsync(() => AppDatabase.instance.writeMeta('list_view', '1'));
      await tester.runAsync(() async => reloaded = await AppSettings.load());
      expect(reloaded.deckView, DeckView.list);

      await pickView(tester, s.viewDeck);
      await settleIo(tester);
      expect(find.byType(NodeTile), findsNothing);
      expect(find.byType(NodeCard), findsWidgets);
    });

    testWidgets('karoda fotoğraf, klasörün içindekiler, adet ve damga görünür', (tester) async {
      await boot(tester);
      late String dolap;
      await tester.runAsync(() async {
        final d = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Dolap');
        dolap = d.id;
        await store.commit(d);
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Boş kutu'));
        await addPhotoItem('Matkap');
        await addPhotoItem('Testere');
        final testere = store.childrenOf(Roots.home).firstWhere((n) => n.name == 'Testere');
        await store.move(testere.id, dolap);
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil', quantity: 0));
      });
      await grid(tester);
      Finder inTile(String name, Finder what) => find.descendant(of: find.widgetWithText(NodeTile, name), matching: what);

      expect(inTile('Matkap', find.byType(Image)), findsOneWidget);
      expect(inTile('Dolap', find.byType(Image)), findsOneWidget, reason: 'klasör içindekinin fotoğrafını gösterir');
      expect(inTile('Boş kutu', find.byType(Image)), findsNothing);
      expect(inTile('Pil', find.text(s.outOfStock)), findsOneWidget);
      expect(inTile('Pil', find.text('0')), findsOneWidget);
      expect(inTile('Pil', find.byTooltip(s.increase)), findsNothing, reason: '− / + karoda yok');
    });

    testWidgets('karoya dokununca açılır; ⋯ seçenekleri açar; sürüklenip klasöre konur; yana kaydırma çöpe atmaz', (tester) async {
      await boot(tester);
      final (kutu, pil) = await boxWithBattery(tester);
      await grid(tester);

      // Yana fiske: karoda eylem yok (dar karoda kısa bir fiske çöpe atardı).
      await tester.fling(find.text('Pil'), const Offset(-200, 0), 1400);
      await settleIo(tester);
      expect(store.byId(pil)!.isDeleted, isFalse);

      // Eşyaya dokununca seçenekleriyle öne çıkar; klasörün seçenekleri ⋯ ile.
      await tester.tap(find.text('Pil'));
      await tester.pumpAndSettle();
      expect(find.text(s.edit), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.widgetWithText(NodeTile, 'Kutu'), matching: find.byTooltip(s.options)));
      await tester.pumpAndSettle();
      expect(find.text(s.qrCode), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Uzun basıp klasör karosunun ortasına bırakınca içine girer.
      final g = await pickUp(tester, 'Pil');
      expect(store.draggingId, pil);
      await g.moveTo(tester.getCenter(find.widgetWithText(NodeTile, 'Kutu')));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await settleIo(tester);
      expect(store.byId(pil)!.parentId, kutu);

      // Klasör karosuna dokununca içine girilir; içerisi de ızgaradır.
      await tester.tap(find.text('Kutu'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(NodeTile, 'Pil'), findsOneWidget);
    });

    testWidgets('karolar yan yana sıralanır: sol yarıya bırakılan önüne, sağ yarıya bırakılan arkasına girer', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        for (final name in ['Bir', 'İki', 'Üç']) {
          await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name));
        }
      });
      await grid(tester);
      List<String> order() => [for (final n in store.childrenOf(Roots.home)) n.name];
      expect(order(), ['Bir', 'İki', 'Üç']);

      var g = await pickUp(tester, 'Üç');
      var target = tester.getRect(find.widgetWithText(NodeTile, 'Bir'));
      await g.moveTo(Offset(target.left + 14, target.center.dy));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await settleIo(tester);
      expect(order(), ['Üç', 'Bir', 'İki']);

      g = await pickUp(tester, 'Üç');
      target = tester.getRect(find.widgetWithText(NodeTile, 'Bir'));
      await g.moveTo(Offset(target.right - 14, target.center.dy));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await settleIo(tester);
      expect(order(), ['Bir', 'Üç', 'İki']);

      // Toplu seçim karolarda da çalışır.
      await tester.tap(find.text('Bir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.select));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İki'));
      await tester.pumpAndSettle();
      expect(find.text(s.selectedCount(2)), findsOneWidget);
    });

    testWidgets('dar ekranda ve yazı 2 katken karolar taşmaz; geniş ekranda sütun artar', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await boot(tester, size: const Size(320, 640));
      await tester.runAsync(() async {
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Mutfak dolabının üst rafı', isFull: true));
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item)
            .copyWith(name: 'Çok uzun adlı bir yedek parça', quantity: 120, minQuantity: 200));
      });
      await grid(tester);
      expect(find.byType(NodeTile), findsNWidgets(2));
      final narrow = tester.getRect(find.byType(NodeTile).first).width;
      expect(narrow, greaterThan(100), reason: '320 dp\'de iki sütun');

      tester.view.physicalSize = const Size(900, 600) * 2;
      await tester.pumpAndSettle();
      final wide = tester.getRect(find.byType(NodeTile).first).width;
      expect(wide, lessThan(150), reason: 'geniş ekranda karo büyümez, sütun artar');
    });
  });

  group('liste görünümü', () {
    Future<void> seed(WidgetTester tester, int items) async {
      await tester.runAsync(() async {
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu'));
        for (var i = 1; i <= items; i++) {
          await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Eşya $i'));
        }
      });
      await tester.pumpAndSettle();
    }

    testWidgets('alttaki düğme desteyi sık satırlara çevirir; ekrana daha çok kayıt sığar, seçim hatırlanır', (tester) async {
      await boot(tester);
      await seed(tester, 14);
      final cardsShown = find.byType(NodeCard).evaluate().length;
      expect(find.byType(NodeRow), findsNothing);
      expect(find.text('Eşya 9'), findsNothing, reason: 'destede bu kadar aşağısı görünmez');

      await pickView(tester, s.viewList);
      await settleIo(tester);
      expect(store.settings.listView, isTrue);
      expect(find.byType(NodeCard), findsNothing);
      final rowsShown = find.byType(NodeRow).evaluate().length;
      expect(rowsShown, greaterThan(cardsShown), reason: 'aynı ekranda daha çok kayıt');
      expect(find.text('Eşya 9'), findsOneWidget);
      // Satırlar üst üste binmez.
      final first = tester.getRect(find.widgetWithText(NodeRow, 'Eşya 1'));
      final second = tester.getRect(find.widgetWithText(NodeRow, 'Eşya 2'));
      expect(second.top, greaterThanOrEqualTo(first.bottom));
      expect(first.height, NodeRow.height);
      expect(find.text(s.items), findsOneWidget, reason: 'klasör/eşya grupları listede de ayrı');

      // Ayar veritabanında: yeniden açılınca liste olarak gelir.
      late AppSettings reloaded;
      await tester.runAsync(() async => reloaded = await AppSettings.load());
      expect(reloaded.listView, isTrue);

      await pickView(tester, s.viewDeck);
      await settleIo(tester);
      expect(find.byType(NodeRow), findsNothing);
      expect(find.byType(NodeCard), findsWidgets);
    });

    testWidgets('listede satırlar sağ kenardaki kulpların altına girmez; destede kart genişliği aynı kalır', (tester) async {
      await boot(tester);
      await seed(tester, 3);
      const screen = 411.0;
      const handle = 22.0; // kulbun eni
      expect(tester.getRect(find.widgetWithText(NodeCard, 'Eşya 1')).width, screen - 32, reason: 'deste: kart tam genişlikte');

      await pickView(tester, s.viewList);
      await settleIo(tester);
      final row = find.widgetWithText(NodeRow, 'Eşya 1');
      expect(tester.getRect(row).right, lessThanOrEqualTo(screen - handle - 6), reason: 'satır kulptan uzak biter');
      final more = tester.getRect(find.descendant(of: row, matching: find.byTooltip(s.options)));
      expect(more.right, lessThan(screen - handle - 6), reason: '⋯ kulbun altında değil');
      expect(tester.getRect(row).left, 16);

      // Yatayda kulplar başlıkta: satırlar kenara kadar uzanır (pay yok).
      tester.view.physicalSize = const Size(900, 411) * 2;
      await tester.pumpAndSettle();
      final rows = find.byType(NodeRow).evaluate().map((e) => tester.getRect(find.byWidget(e.widget)));
      final rightmost = rows.map((r) => r.right).reduce((a, b) => a > b ? a : b);
      expect(rightmost, closeTo(900 - 16, 0.5));
    });

    testWidgets('listede klasör satırı sekmeli klasör biçiminde, eşya satırı düz; boyları aynı', (tester) async {
      await boot(tester);
      await seed(tester, 1);
      await pickView(tester, s.viewList);
      await settleIo(tester);

      ShapeBorder shapeOf(String name) {
        final box = tester.widget<AnimatedContainer>(
          find.descendant(of: find.widgetWithText(NodeRow, name), matching: find.byType(AnimatedContainer)).first,
        );
        return (box.decoration! as ShapeDecoration).shape;
      }

      final folder = shapeOf('Kutu');
      expect(folder, isA<FolderBorder>());
      expect(shapeOf('Eşya 1'), isA<RoundedRectangleBorder>());
      expect(tester.getSize(find.widgetWithText(NodeRow, 'Kutu')).height, NodeRow.height);
      expect(tester.getSize(find.widgetWithText(NodeRow, 'Eşya 1')).height, NodeRow.height);

      // Sekme solda, simgenin üstünde: orası dolu; sağ üst köşe (sekmenin dışı) boş.
      const rect = Rect.fromLTWH(0, 0, 360, NodeRow.height);
      final path = folder.getOuterPath(rect);
      expect(path.contains(const Offset(30, 2)), isTrue, reason: 'sekmenin içi');
      expect(path.contains(const Offset(200, 2)), isFalse, reason: 'sekmenin dışında üst kenar aşağıda');
      expect(path.contains(const Offset(200, NodeRow.folderNotch + 2)), isTrue);
    });

    testWidgets('satırda da aynı: dokununca açılır, adet değişir, sürüklenip klasöre konur', (tester) async {
      await boot(tester);
      late String pil;
      late String kutu;
      await tester.runAsync(() async {
        final k = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
        await store.commit(k);
        kutu = k.id;
        final p = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil', quantity: 3);
        await store.commit(p);
        pil = p.id;
        await store.updateSettings(store.settings.copyWith(listView: true));
      });
      await tester.pumpAndSettle();
      expect(find.byType(NodeRow), findsNWidgets(2));

      // Adet satırdan değişir.
      await tester.tap(find.descendant(of: find.widgetWithText(NodeRow, 'Pil'), matching: find.byTooltip(s.increase)));
      await settleIo(tester);
      expect(store.byId(pil)!.quantity, 4);
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      // Eşyaya dokununca seçenekleriyle öne çıkar.
      await tester.tap(find.text('Pil'));
      await tester.pumpAndSettle();
      expect(find.text(s.edit), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Uzun basıp klasör satırının ortasına bırakınca içine girer.
      final g = await pickUp(tester, 'Pil');
      expect(store.draggingId, pil);
      await g.moveTo(tester.getCenter(find.widgetWithText(NodeRow, 'Kutu')));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await settleIo(tester);
      expect(store.byId(pil)!.parentId, kutu);

      // Klasör satırına dokununca içine girilir.
      await tester.tap(find.text('Kutu'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(NodeRow, 'Pil'), findsOneWidget);
    });

    testWidgets('satırlar sürüklenerek sıralanır; toplu seçim satırlarda da çalışır', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        for (final name in ['Bir', 'İki', 'Üç']) {
          await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name));
        }
        await store.updateSettings(store.settings.copyWith(listView: true));
      });
      await tester.pumpAndSettle();
      expect(store.childrenOf(Roots.home).map((n) => n.name), ['Bir', 'İki', 'Üç']);

      // "Üç" satırı "Bir"in üst yarısına bırakılır: başa geçer.
      final g = await pickUp(tester, 'Üç');
      final target = tester.getRect(find.widgetWithText(NodeRow, 'Bir'));
      await g.moveTo(Offset(target.center.dx, target.top + 8));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await settleIo(tester);
      expect(store.childrenOf(Roots.home).map((n) => n.name), ['Üç', 'Bir', 'İki']);

      await tester.tap(find.descendant(of: find.widgetWithText(NodeRow, 'Bir'), matching: find.byTooltip(s.options)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.select));
      await tester.pumpAndSettle();
      await tester.tap(find.text('İki'));
      await tester.pumpAndSettle();
      expect(find.text(s.selectedCount(2)), findsOneWidget);
    });
  });

  group('sıralama', () {
    Future<void> seed(WidgetTester tester) async {
      await tester.runAsync(() async {
        for (final name in ['Zımba', 'Bant', 'Makas']) {
          await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: name));
          await Future<void>.delayed(const Duration(milliseconds: 3));
        }
      });
      await tester.pumpAndSettle();
    }

    List<String> onScreen(WidgetTester tester) {
      final cards = find.byType(NodeCard).evaluate().map((e) => e.widget as NodeCard).toList()
        ..sort((a, b) => tester
            .getTopLeft(find.byWidget(a))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b)).dy));
      return [for (final c in cards) c.node.name];
    }

    testWidgets('alttaki düğmeden "Ada göre" seçilince kartlar A–Z dizilir; elle sıra saklanır', (tester) async {
      await boot(tester);
      await seed(tester);
      expect(onScreen(tester), ['Zımba', 'Bant', 'Makas']);
      expect(find.text(s.searchInventory), findsOneWidget, reason: 'üç düğmeyle de arama yazısı sığar');
      // Düğmeler sıkı dizildi ama çubuk incelmedi, dokunma alanı küçülmedi.
      final sortBox = tester.getSize(find.byTooltip(s.sortTitle));
      expect(sortBox.height, greaterThanOrEqualTo(48));
      expect(sortBox.width, greaterThanOrEqualTo(40));
      expect(tester.getSize(find.byType(ViewModeButton)).height, greaterThanOrEqualTo(48));

      await tester.tap(find.byTooltip(s.sortTitle));
      await tester.pumpAndSettle();
      for (final label in [s.sortManual, s.sortName, s.sortNewest, s.sortExpiry]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text(s.sortName));
      await settleIo(tester);
      expect(store.settings.deckSort, DeckSort.name);
      expect(onScreen(tester), ['Bant', 'Makas', 'Zımba']);
      expect(store.childrenOf(Roots.home).map((n) => n.name), ['Zımba', 'Bant', 'Makas'], reason: 'elle sıra duruyor');

      await tester.tap(find.byTooltip(s.sortTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.sortNewest));
      await settleIo(tester);
      expect(onScreen(tester), ['Makas', 'Bant', 'Zımba']);
    });

    testWidgets('sıralıyken araya bırakmak sırayı değiştirmez; nedeni yazar, "Benim sıram" bir dokunuş', (tester) async {
      await boot(tester);
      await seed(tester);
      await tester.runAsync(() => store.updateSettings(store.settings.copyWith(deckSort: DeckSort.name)));
      await tester.pumpAndSettle();
      expect(onScreen(tester), ['Bant', 'Makas', 'Zımba']);

      final g = await pickUp(tester, 'Zımba');
      final target = tester.getRect(find.widgetWithText(NodeCard, 'Bant'));
      await g.moveTo(Offset(target.center.dx, target.top + 12));
      await tester.pump(const Duration(milliseconds: 100));
      await g.up();
      await settleIo(tester);
      expect(find.text(s.sortedNoManual(s.sortName)), findsOneWidget);
      expect(store.childrenOf(Roots.home).map((n) => n.name), ['Zımba', 'Bant', 'Makas'], reason: 'elle sıra değişmedi');

      await tester.tap(find.widgetWithText(SnackBarAction, s.sortManual));
      await settleIo(tester);
      expect(store.settings.deckSort, DeckSort.manual);
      expect(onScreen(tester), ['Zımba', 'Bant', 'Makas']);
    });
  });

  group('barkod', () {
    const code = '8690504012345';

    /// Tarayıcıdan dönen barkodun gereği yapılır (kamera olmadan).
    void scanned(WidgetTester tester, {String? parentId}) {
      final context = tester.element(find.byType(NodeListView).last);
      unawaited(openScanned(context, const ScannedCode.barcode(code), parentId: parentId));
    }

    testWidgets('okutulan barkod eşyayı bulur; aynı barkodla iki kayıt varsa hangisi olduğu sorulur', (tester) async {
      await boot(tester);
      final (kutu, pil) = await boxWithBattery(tester, inside: true);
      await tester.runAsync(() => store.commit(store.byId(pil)!.copyWith(barcode: code)));
      await tester.pumpAndSettle();

      scanned(tester);
      await tester.pumpAndSettle();
      // Eşya, klasörünün içinde olsa da seçenekleriyle öne çıkar.
      expect(find.text(s.edit), findsWidgets);
      expect(find.text('Pil'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Aynı üründen bir tane daha, başka yerde.
      await tester.runAsync(
        () => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Yedek pil', barcode: code)),
      );
      await tester.pumpAndSettle();
      scanned(tester);
      await tester.pumpAndSettle();
      expect(find.text(s.barcodeMatches(2)), findsOneWidget);
      expect(find.textContaining(store.nameOf(store.byId(kutu)!)), findsWidgets, reason: 'yeriyle listelenir');
      await tester.tap(find.widgetWithText(RecordTile, 'Yedek pil'));
      await tester.pumpAndSettle();
      expect(find.text(s.barcodeMatches(2)), findsNothing);
      expect(find.text(s.edit), findsWidgets);
    });

    testWidgets('kayıtlı olmayan barkod: bu barkodla yeni eşya açılır, kaydedilince barkodu durur', (tester) async {
      await boot(tester);
      final (kutu, _) = await boxWithBattery(tester);
      scanned(tester, parentId: kutu);
      await tester.pumpAndSettle();
      expect(find.text(s.barcodeUnknown), findsOneWidget);
      expect(find.text(code), findsOneWidget);

      // Vazgeçilirse hiçbir şey olmaz.
      await tester.tap(find.text(s.cancel));
      await tester.pumpAndSettle();
      expect(store.byBarcode(code), isEmpty);
      expect(find.byType(NodeEditorPage), findsNothing);

      scanned(tester, parentId: kutu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.newItemWithBarcode));
      await tester.pumpAndSettle();
      expect(find.byType(NodeEditorPage), findsOneWidget);
      expect(find.text(code), findsOneWidget, reason: 'barkodu olan eşyada "Diğer" açık gelir');
      await tester.enterText(find.descendant(of: find.byType(NodeCard), matching: find.byType(TextField)), 'Kalem pil');
      await tester.tap(find.text(s.save));
      await settleIo(tester);
      final saved = store.byBarcode(code).single;
      expect(saved.name, 'Kalem pil');
      expect(saved.parentId, kutu, reason: 'tarayıcının açıldığı seviyede başlar');

      // Artık okutunca bulunur.
      scanned(tester);
      await tester.pumpAndSettle();
      expect(find.text(s.barcodeUnknown), findsNothing);
      expect(find.text(s.edit), findsWidgets);
    });

    testWidgets('düzenleyicide barkod elle yazılır, kaldırılır; başka eşyada da varsa söylenir', (tester) async {
      await boot(tester);
      final (_, pil) = await boxWithBattery(tester);
      await tester.runAsync(
        () => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Yedek pil', barcode: code)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.edit).last);
      await tester.pumpAndSettle();
      await openSection(tester, s.moreActions);
      final row = find.widgetWithText(PaperRow, s.barcode);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      expect(find.text(s.barcodeHint), findsOneWidget);
      expect(find.byTooltip(s.scanBarcode), findsOneWidget, reason: 'kamerayla okutma düğmesi');

      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), ' $code ');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
      await tester.pumpAndSettle();
      expect(find.text(code), findsOneWidget);
      expect(find.text(s.barcodeAlsoOn('Yedek pil')), findsWidgets, reason: 'aynı barkod başka eşyada: engel değil, bilgi');

      await tester.tap(find.text(s.save));
      await settleIo(tester);
      expect(store.byId(pil)!.barcode, code);
      expect(store.byBarcode(code), hasLength(2));

      // Boş bırakıp kaydedince barkod kalkar.
      tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).first).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.edit).last);
      await tester.pumpAndSettle();
      final again = find.widgetWithText(PaperRow, s.barcode);
      await tester.ensureVisible(again);
      await tester.pumpAndSettle();
      await tester.tap(again);
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
      await tester.pumpAndSettle();
      expect(find.text(s.barcodeHint), findsOneWidget);
      await tester.tap(find.text(s.save));
      await settleIo(tester);
      expect(store.byId(pil)!.barcode, isNull);
      expect(store.byBarcode(code).single.name, 'Yedek pil');
    });
  });

  group('ekler', () {
    const channel = MethodChannel('envanter/platform');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'openUrl' || call.method == 'openFile' ? true : null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    Future<String> openEditor(WidgetTester tester, {List<Attachment> attachments = const []}) async {
      late String id;
      await tester.runAsync(() async {
        final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap', attachments: attachments);
        await store.commit(n);
        id = n.id;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Matkap'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.edit).last);
      await tester.pumpAndSettle();
      return id;
    }

    Future<void> showAttachments(WidgetTester tester) async {
      // Eki olmayan kayıtta bölüm kapalı gelir; olanında açık.
      if (find.text(s.addAttachment).evaluate().isEmpty) await openSection(tester, s.attachments);
      await tester.ensureVisible(find.text(s.addAttachment));
      await tester.pumpAndSettle();
    }

    testWidgets('düzenleyici açıkken gelen ek kaydedince kaybolmaz; bu arada çıkarılan ek geri gelmez', (tester) async {
      await boot(tester);
      Attachment link(String id) =>
          Attachment(id: id, name: id, addedAt: DateTime(2026, 9, 1), url: 'https://ornek.com/$id');
      final id = await openEditor(tester, attachments: [link('kilavuz'), link('garanti')]);

      // Düzenleyici açıkken kayıt değişir (karşıdan gelmiş gibi): video eklendi, garanti çıkarıldı.
      await tester.runAsync(() async {
        final now = store.byId(id)!;
        await store.commit(
          now.copyWith(attachments: [now.attachments.firstWhere((a) => a.id == 'kilavuz'), link('video')]),
        );
      });
      expect(store.byId(id)!.attachmentTombs.keys, ['garanti']);

      // Kullanıcı yalnızca adı değiştirip kaydeder (taslağında hâlâ eski iki ek var).
      await tester.enterText(find.descendant(of: find.byType(NodeCard), matching: find.byType(TextField)), 'Darbeli matkap');
      await tester.tap(find.text(s.save));
      await settleIo(tester);
      final saved = store.byId(id)!;
      expect(saved.name, 'Darbeli matkap');
      expect([for (final a in saved.attachments) a.id], unorderedEquals(['kilavuz', 'video']),
          reason: 'gelen ek korunur, çıkarılan geri gelmez');
      expect(saved.attachmentTombs.keys, ['garanti'], reason: 'video için iz konmaz, garantinin izi durur');
    });

    testWidgets('düzenleyici açıkken gelen adet değişikliği kaydedince geri alınmaz', (tester) async {
      await boot(tester);
      final id = await openEditor(tester);

      // Düzenleyici açıkken kayıt değişir (karşıdan gelmiş gibi): adet 2 oldu.
      await tester.runAsync(() async => store.commit(store.byId(id)!.copyWith(quantity: 2)));

      // Kullanıcı yalnızca adı değiştirip kaydeder (taslağında adet hâlâ boş).
      await tester.enterText(find.descendant(of: find.byType(NodeCard), matching: find.byType(TextField)), 'Darbeli matkap');
      await tester.tap(find.text(s.save));
      await settleIo(tester);
      final saved = store.byId(id)!;
      expect(saved.name, 'Darbeli matkap');
      expect(saved.quantity, 2, reason: 'taslaktaki eski adet geri yazılmaz');
    });

    testWidgets('düzenleyicide bağlantı eklenir; kartta ataş çıkar, odak görünümünden tarayıcıda açılır', (tester) async {
      await boot(tester);
      final id = await openEditor(tester);
      await showAttachments(tester);
      expect(find.text(s.attachmentsHint), findsOneWidget, reason: 'boşken ne eklenebileceği yazar');

      await tester.tap(find.text(s.addAttachment));
      await tester.pumpAndSettle();
      for (final option in [s.attachDocument, s.takePhoto, s.attachRecordVideo, s.attachFromGallery, s.attachLink]) {
        expect(find.text(option), findsOneWidget);
      }
      await tester.tap(find.text(s.attachLink));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'youtube.com/watch?v=matkap');
      await tester.enterText(fields.at(1), 'Nasıl kullanılır');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
      await tester.pumpAndSettle();
      expect(find.text('Nasıl kullanılır'), findsOneWidget);
      expect(find.text('youtube.com'), findsOneWidget, reason: 'adın altında site');
      expect(store.byId(id)!.attachments, isEmpty, reason: 'kaydedilene dek taslakta');

      await tester.tap(find.text(s.save));
      await settleIo(tester);
      final saved = store.byId(id)!.attachments.single;
      expect(saved.url, 'https://youtube.com/watch?v=matkap');
      expect(saved.name, 'Nasıl kullanılır');

      // Kartta ataş ve ek sayısı.
      final card = find.ancestor(of: find.text('Matkap'), matching: find.byType(NodeCard));
      expect(find.descendant(of: card, matching: find.byIcon(Icons.attach_file_rounded)), findsOneWidget);

      // Karta dokununca ekler şeritte; eke dokununca tarayıcı açılır.
      await tester.tap(find.text('Matkap'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nasıl kullanılır'));
      await tester.pumpAndSettle();
      final open = calls.singleWhere((c) => c.method == 'openUrl');
      expect((open.arguments as Map)['url'], 'https://youtube.com/watch?v=matkap');
    });

    testWidgets('geçersiz adres bağlantı olmaz', (tester) async {
      await boot(tester);
      await openEditor(tester);
      await showAttachments(tester);
      await tester.tap(find.text(s.addAttachment));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.attachLink));
      await tester.pumpAndSettle();
      final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'merhaba');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
      await tester.pumpAndSettle();
      expect(find.text(s.linkInvalid), findsOneWidget);
      expect(find.text(s.attachmentsHint), findsOneWidget, reason: 'hiçbir şey eklenmedi');
    });

    testWidgets('ek yeniden adlandırılır ve kaldırılır; kaydedince dosyası da silinir', (tester) async {
      await boot(tester);
      const rel = 'files/kilavuz.pdf';
      File(AppPaths.abs(rel))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      AppPaths.forget(rel);
      final id = await openEditor(tester, attachments: [
        Attachment(
          id: 'a1',
          name: 'kilavuz',
          addedAt: DateTime(2026, 9, 1),
          file: rel,
          mime: 'application/pdf',
          size: 3 * 1024 * 1024,
        ),
        Attachment(id: 'a2', name: 'Video', addedAt: DateTime(2026, 9, 1), url: 'https://ornek.com/v'),
      ]);
      await showAttachments(tester);
      expect(find.text('PDF · 3 MB'), findsOneWidget);

      // Dokununca telefonda o türü açan uygulamaya verilir.
      await tester.tap(find.text('kilavuz'));
      await tester.pumpAndSettle();
      final opened = calls.singleWhere((c) => c.method == 'openFile');
      expect((opened.arguments as Map)['mime'], 'application/pdf');
      expect((opened.arguments as Map)['path'], AppPaths.abs(rel));

      await tester.tap(find.byTooltip(s.options).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.renameAttachment));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Kullanım kılavuzu',
      );
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
      await tester.pumpAndSettle();
      expect(find.text('Kullanım kılavuzu'), findsOneWidget);

      await tester.tap(find.byTooltip(s.options).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.removeAttachment));
      await tester.pumpAndSettle();
      expect(find.text('Kullanım kılavuzu'), findsNothing);
      expect(File(AppPaths.abs(rel)).existsSync(), isTrue, reason: 'kaydedilene dek dosya durur (vazgeçilebilir)');

      await tester.tap(find.text(s.save));
      await settleIo(tester);
      expect(store.byId(id)!.attachments.single.name, 'Video');
      expect(File(AppPaths.abs(rel)).existsSync(), isFalse, reason: 'artık hiçbir kayıt kullanmıyor');
    });

    testWidgets('bu cihaza inmemiş ek açılmaz, nedeni söylenir; odak görünümünden bağlantı eklenir', (tester) async {
      await boot(tester);
      late String id;
      await tester.runAsync(() async {
        final n = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap', attachments: [
              Attachment(
                id: 'v',
                name: 'Sorun videosu',
                addedAt: DateTime(2026, 9, 1),
                file: 'files/gelmedi.mp4',
                mime: 'video/mp4',
                size: 48 * 1024 * 1024,
              ),
            ]);
        await store.commit(n);
        id = n.id;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Matkap'));
      await tester.pumpAndSettle();
      expect(find.text('${s.attachmentVideo} · 48 MB · ${s.attachmentNotHereShort}'), findsOneWidget);
      await tester.tap(find.text('Sorun videosu'));
      await tester.pumpAndSettle();
      // Bildirim hem katmanın hem alttaki ekranın iskelesinde çıkar (üst üste, tek görünür).
      expect(find.text(s.attachmentNotHere), findsWidgets);
      expect(calls.where((c) => c.method == 'openFile'), isEmpty);

      // Karşıdan inmeye başlayınca yüzdesi yazar; bitince ya da kesilince eski haline döner.
      sharing.fileProgress.value = const {'files/gelmedi.mp4': 40};
      await tester.pump();
      expect(find.text('${s.attachmentVideo} · 48 MB · ${s.attachmentDownloading(40)}'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      sharing.fileProgress.value = const {'files/gelmedi.mp4': 85};
      await tester.pump();
      expect(find.text('${s.attachmentVideo} · 48 MB · ${s.attachmentDownloading(85)}'), findsOneWidget);
      sharing.fileProgress.value = const {};
      await tester.pumpAndSettle();
      expect(find.text('${s.attachmentVideo} · 48 MB · ${s.attachmentNotHereShort}'), findsOneWidget);

      // Şeridin sonundaki + ile, düzenleyiciye girmeden.
      await tester.tap(find.byTooltip(s.addAttachment));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.attachLink));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first,
        'https://ornek.com/kilavuz.pdf',
      );
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
      await settleIo(tester);
      expect(store.byId(id)!.attachments.map((a) => a.name), ['Sorun videosu', 'ornek.com']);
      expect(find.text('ornek.com'), findsWidgets, reason: 'katman kapanmadan şeritte görünür');
    });

    testWidgets('Ayarlar\'da kaplanan yer yazar; dokununca en büyük ekler kayıtlarıyla listelenir', (tester) async {
      await boot(tester);
      for (final (rel, size) in [('files/video.mp4', 3 * 1024 * 1024), ('files/kilavuz.pdf', 200 * 1024)]) {
        File(AppPaths.abs(rel))
          ..createSync(recursive: true)
          ..writeAsBytesSync(List.filled(size, 0));
        AppPaths.forget(rel);
      }
      await tester.runAsync(() => store.commit(
            store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap', attachments: [
              Attachment(id: 'k', name: 'Kılavuz', addedAt: DateTime(2026), file: 'files/kilavuz.pdf', mime: 'application/pdf', size: 200 * 1024),
              Attachment(id: 'v', name: 'Sorun videosu', addedAt: DateTime(2026), file: 'files/video.mp4', mime: 'video/mp4', size: 3 * 1024 * 1024),
            ]),
          ));
      await tester.pumpAndSettle();

      unawaited(Navigator.of(tester.element(find.byType(HomeScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const SettingsPage())));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.settingsInventory));
      await tester.pumpAndSettle();
      final scroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
      await tester.scrollUntilVisible(find.text(s.storageTitle), 300, scrollable: scroll);
      await settleIo(tester);
      expect(find.text(s.storageSummary(0, 2)), findsOneWidget);
      expect(find.text('3,2 MB'), findsOneWidget);

      await tester.ensureVisible(find.text(s.storageTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.storageTitle));
      await tester.pumpAndSettle();
      expect(find.text(s.storageMeasuring), findsOneWidget, reason: 'ölçüm sürerken dönen simge değil yazı');
      await settleIo(tester);
      expect(find.text(s.upper(s.storageLargest)), findsOneWidget);
      // Büyük olan üstte; hangi kayıtta olduğu yazar.
      final video = tester.getTopLeft(find.text('Sorun videosu')).dy;
      final manual = tester.getTopLeft(find.text('Kılavuz')).dy;
      expect(video, lessThan(manual));
      expect(find.textContaining('Matkap ·'), findsNWidgets(2));
      expect(find.text('3 MB'), findsOneWidget);

      // Dokununca kaydı açılır.
      await tester.tap(find.text('Sorun videosu'));
      await tester.pumpAndSettle();
      expect(find.text(s.edit), findsWidgets);
    });

    testWidgets('aramada ekinin adıyla bulunan kayıtta ekin adı görünür', (tester) async {
      await boot(tester);
      await tester.runAsync(() => store.commit(
            store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap', attachments: [
              Attachment(id: 'k', name: 'Kullanım kılavuzu', addedAt: DateTime(2026, 9, 1), url: 'https://ornek.com/k'),
            ]),
          ));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.searchInventory));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'kilavuz');
      await tester.pumpAndSettle();
      expect(find.text('Matkap'), findsOneWidget);
      expect(find.text('Kullanım kılavuzu'), findsOneWidget);
    });
  });

  group('ana ekran kısayolu', () {
    const channel = MethodChannel('envanter/platform');
    String? pending;

    setUp(() {
      pending = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method != 'takeShortcut') return null;
        final shortcut = pending;
        pending = null;
        return shortcut;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    testWidgets('widget\'a dokununca alışveriş listesi açılır; liste widget\'a yazılır', (tester) async {
      final sent = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'updateShoppingWidget') {
          sent.add(call.arguments as String);
          return true;
        }
        if (call.method != 'takeShortcut') return null;
        final shortcut = pending;
        pending = null;
        return shortcut;
      });
      pending = 'shopping';
      await boot(tester);
      expect(find.byType(ShoppingPage), findsOneWidget);
      expect(sent, isNotEmpty, reason: 'açılışta liste yazılır');

      await tester.runAsync(() => store.commit(
            store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
              name: 'Pil',
              quantity: 0,
              wantedAt: DateTime.now(),
            ),
          ));
      await settleIo(tester);
      expect(find.text('Pil'), findsOneWidget, reason: 'sayfada');
      expect(sent.last, contains('"Pil"'), reason: 'widget\'ta');
      final count = sent.length;
      // Listeyi etkilemeyen değişiklik yeniden yazdırmaz.
      await tester.runAsync(() => store.updateSettings(store.settings.copyWith(favorites: const [])));
      await settleIo(tester);
      expect(sent.length, count);
    });

    testWidgets('uygulama "Ara" kısayoluyla açılınca arama açılır', (tester) async {
      pending = 'search';
      await boot(tester);
      expect(find.byType(SearchPage), findsOneWidget);
    });

    testWidgets('"Yeni eşya" kısayoluyla açılınca eşya kaldığı klasöre başlar', (tester) async {
      await boot(tester);
      final (kutu, _) = await boxWithBattery(tester, inside: true);
      await tester.tap(find.text('Kutu'));
      await tester.pumpAndSettle();
      expect(store.settings.lastLevel, kutu);

      // Android sabit kısayolda etkinliği baştan kurar: arayüz sıfırdan açılır.
      // Ana ekranın kabuğu ilk çizimde son seviyeyi "ana ekran" diye ezse de
      // eşya geri kurulan klasöre başlamalı.
      pending = 'new_item';
      await tester.pumpWidget(EnvanterApp(key: UniqueKey(), store: store, sharing: sharing));
      await tester.pumpAndSettle();
      final editor = tester.widget<NodeEditorPage>(find.byType(NodeEditorPage));
      expect(editor.isNew, isTrue);
      expect(editor.node.parentId, kutu);
      await settleIo(tester);
    });

    testWidgets('son açık klasörün üstü çöpteyse açılış ve "Yeni eşya" ana ekranda', (tester) async {
      await boot(tester);
      await tester.runAsync(() async {
        final kutu = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Kutu');
        await store.commit(kutu);
        final raf = store.draft(parentId: kutu.id, kind: NodeKind.container).copyWith(name: 'Raf');
        await store.commit(raf);
        // Uygulama kapalıyken başka telefondan Kutu çöpe atıldı; kayıtlı son yer Raf kaldı (kendisi işaretsiz).
        await store.moveToTrash(kutu.id);
        await store.updateSettings(store.settings.copyWith(lastLevel: raf.id));
      });
      pending = 'new_item';
      await tester.pumpWidget(EnvanterApp(key: UniqueKey(), store: store, sharing: sharing));
      await tester.pumpAndSettle();
      expect(find.byType(ContainerScreen, skipOffstage: false), findsNothing);
      final editor = tester.widget<NodeEditorPage>(find.byType(NodeEditorPage));
      expect(editor.node.parentId, isNull, reason: 'yeni eşya çöpteki klasörde başlamasın');
      await settleIo(tester);
    });

    testWidgets('uygulama açıkken "Yeni eşya" kısayolu açık klasöre eşya başlatır', (tester) async {
      await boot(tester);
      final (kutu, _) = await boxWithBattery(tester);
      await tester.tap(find.text('Kutu'));
      await tester.pumpAndSettle();
      expect(store.settings.lastLevel, kutu);

      // Yerel taraf "kısayola basıldı" der; Flutter kısayolu kendisi alır.
      pending = 'new_item';
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('shortcut')),
        (_) {},
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<NodeEditorPage>(find.byType(NodeEditorPage));
      expect(editor.isNew, isTrue);
      expect(editor.node.kind, NodeKind.item);
      expect(editor.node.parentId, kutu);
    });
  });

  group('değer', () {
    testWidgets('düzenleyicide fiyat ve seri no girilir; odak katmanında ve Değer sayfasında görünür', (tester) async {
      await boot(tester);
      final (_, pil) = await boxWithBattery(tester, inside: true);
      // Varsayılan birim telefonun bölgesinden gelir; test makinesine bağlı kalmasın.
      await tester.runAsync(() => store.updateSettings(store.settings.copyWith(currency: 'TRY')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kutu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pil'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.edit).last);
      await tester.pumpAndSettle();
      await openSection(tester, s.valueSection);

      Future<void> prompt(String row, String text) async {
        await tester.ensureVisible(find.text(row));
        await tester.pumpAndSettle();
        await tester.tap(find.text(row));
        await tester.pumpAndSettle();
        await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), text);
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
        await tester.pumpAndSettle();
      }

      // Anlaşılmayan tutar yazılmaz, nedeni söylenir.
      await prompt(s.priceTitle, '12,5,0');
      expect(find.text(s.priceInvalid), findsOneWidget);
      await prompt(s.priceTitle, '1.250,50');
      expect(find.text('1.250,50 ₺'), findsOneWidget);
      await prompt(s.serialTitle, 'sn-123');
      expect(find.text('SN-123'), findsNothing, reason: 'yazıldığı gibi saklanır');
      expect(find.text('sn-123'), findsOneWidget);
      await tester.tap(find.text(s.save).first);
      await settleIo(tester);
      expect(store.byId(pil)!.price, '1250.50 TRY');
      expect(store.byId(pil)!.serial, 'sn-123');

      // Odak katmanı: fiyat ve dokununca kopyalanan seri no.
      await tester.tap(find.text('Pil'));
      await tester.pumpAndSettle();
      expect(find.text(s.itemValue('1.250,50 ₺')), findsOneWidget);
      expect(find.text('${s.serialTitle}: sn-123'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Klasörün odağında içindekilerin toplamı.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.widgetWithText(NodeCard, 'Kutu'), matching: find.byTooltip(s.options)));
      await tester.pumpAndSettle();
      expect(find.text(s.contentsValue('1.250,50 ₺')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Sol menüden Değer sayfası: toplam ve yer.
      await tester.tap(find.byTooltip(s.menu));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.valuePageTitle));
      await tester.pumpAndSettle();
      expect(find.text('1.250,50 ₺'), findsWidgets);
      expect(find.widgetWithText(PaperRow, 'Kutu'), findsOneWidget);
      expect(find.text(s.valueReport), findsOneWidget);
    });
  });

  group('seri ekleme', () {
    testWidgets('çekilenler yazılan adlarla klasöre eklenir; boş ad Adsız N olur; çıkarılan fotoğraf silinir', (tester) async {
      await boot(tester);
      final (kutu, _) = await boxWithBattery(tester);
      // Kamera yok: dört "çekilmiş" fotoğraf envanterin resim klasörüne konur.
      final shots = <String>[];
      await tester.runAsync(() async {
        Directory(p.join(AppPaths.docsDir, 'images')).createSync(recursive: true);
        for (var i = 0; i < 4; i++) {
          final rel = 'images/seri_$i.jpg';
          final picture = img.Image(width: 48, height: 48)..clear(img.ColorRgb8(200, 60 * i, 90));
          File(p.join(AppPaths.docsDir, rel)).writeAsBytesSync(img.encodeJpg(picture));
          shots.add(rel);
        }
      });
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      final result = nav.push<(int, String)>(
        MaterialPageRoute(builder: (_) => BurstAddPage(parentId: kutu, initialShots: shots)),
      );
      await tester.pumpAndSettle();
      expect(find.text(s.burstTarget('Kutu')), findsOneWidget);
      expect(find.text(s.burstAddItems(4)), findsOneWidget);

      // Sonuncusu çıkarılır: dosyası da gider.
      await tester.tap(find.byTooltip(s.burstRemoveShot).last);
      await tester.pumpAndSettle();
      expect(File(p.join(AppPaths.docsDir, shots.last)).existsSync(), isFalse);
      expect(find.text(s.burstAddItems(3)), findsOneWidget);

      final fields = find.descendant(of: find.byType(BurstAddPage), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), 'Tencere');
      await tester.enterText(fields.at(2), 'Kepçe');
      await tester.tap(find.text(s.burstAddItems(3)));
      // Kart rengi ve görüntüyle arama izi gerçek dosya işiyle hazırlanır.
      for (var i = 0; i < 200 && find.byType(BurstAddPage).evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.byType(BurstAddPage), findsNothing);
      expect(await result, (3, 'Kutu'));
      final added = store.childrenOf(kutu);
      expect(added.map(store.nameOf), ['Tencere', 'Adsız 1', 'Kepçe'], reason: 'çekim sırasıyla');
      expect(added.map((n) => n.imagePath), shots.take(3));
      expect(added.every((n) => n.kind == NodeKind.item), isTrue);
      await settleIo(tester);
    });

    testWidgets('+ penceresinde üçüncü seçenek seri ekleme; kamerayla mı galeriden mi sorulur', (tester) async {
      await boot(tester);
      await tester.tap(find.byTooltip(s.newRecord).first);
      await tester.pumpAndSettle();
      expect(find.text(s.burstAdd), findsOneWidget);
      expect(find.text(s.burstAddHint), findsOneWidget);
      await tester.tap(find.text(s.burstAdd));
      await tester.pumpAndSettle();
      expect(find.text(s.takePhoto), findsOneWidget);
      expect(find.text(s.burstCameraHint), findsOneWidget);
      expect(find.text(s.pickFromGallery), findsOneWidget);
      expect(find.text(s.burstGalleryHint), findsOneWidget);
    });

    test('galeriden seçilen fotoğrafın adı: galerideki adı, uzantısız', () {
      expect(ImageService.nameOfImage('Vida kutusu.jpg'), 'Vida kutusu');
      expect(ImageService.nameOfImage('IMG_0042.heic'), 'IMG_0042');
      expect(ImageService.nameOfImage('Çay bardağı.JPG'), 'Çay bardağı');
      expect(ImageService.nameOfImage(' Kablo .png'), 'Kablo');
      expect(ImageService.nameOfImage(''), '', reason: 'adı okunamadı: Adsız N olur');
      expect(ImageService.nameOfImage('kablo'), 'kablo');
    });

    /// Sistemin seçicisi ve yerel küçültme testte yok: seçici (adres, galerideki ad) verir, alma dosyayı
    /// kopyalar. [hold]'daki adresin alınması o tamamlanana dek bekler, `bozuk` alınamaz.
    Future<Directory> fakeGallery(WidgetTester tester, List<List<(String, String)>> batches,
        {Map<String, Completer<void>> hold = const {}}) async {
      late Directory gallery;
      await tester.runAsync(() async {
        gallery = Directory.systemTemp.createTempSync('galeri');
        for (final (i, (file, _)) in batches.expand((b) => b).indexed) {
          final picture = img.Image(width: 40, height: 40)..clear(img.ColorRgb8(50 * i, 120, 200));
          File(p.join(gallery.path, '$file.jpg')).writeAsBytesSync(img.encodeJpg(picture));
        }
      });
      final realPick = ImageService.pickGalleryImages;
      final realImport = ImageService.importImage;
      addTearDown(() {
        ImageService.pickGalleryImages = realPick;
        ImageService.importImage = realImport;
      });
      var batch = 0;
      ImageService.pickGalleryImages =
          () async => [for (final (file, name) in batches[batch++]) (p.join(gallery.path, '$file.jpg'), name)];
      ImageService.importImage = (uri, out) async {
        await hold[p.basenameWithoutExtension(uri)]?.future;
        if (p.basenameWithoutExtension(uri) == 'bozuk') return false;
        File(uri).copySync(out);
        return true;
      };
      return gallery;
    }

    Future<void> settleFiles(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 200 && !done(); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    final fields = find.descendant(of: find.byType(BurstAddPage), matching: find.byType(TextField));
    List<String> names(WidgetTester tester) =>
        [for (final f in tester.widgetList<TextField>(fields)) f.controller!.text];
    FilledButton addButton(WidgetTester tester) => tester.widget<FilledButton>(
          find.descendant(of: find.byType(BurstAddPage), matching: find.byType(FilledButton)),
        );

    Future<void> openGallery(WidgetTester tester) async {
      await tester.tap(find.byTooltip(s.newRecord).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.burstAdd));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.pickFromGallery));
      await tester.pumpAndSettle();
    }

    testWidgets('galeriden toplu seçim: satırlar adlarıyla hemen gelir, fotoğraflar ilerlemeyle alınır; '
        'alınamayan düşer; her fotoğraf bir eşya olur', (tester) async {
      await boot(tester);
      final hold = {'img': Completer<void>()};
      await fakeGallery(tester, [
        [('vida', 'Vida kutusu.jpg'), ('bozuk', 'Bozuk.jpg'), ('img', 'IMG_0042.jpg')],
        [('pense', 'Pense.png')],
      ], hold: hold);
      await openGallery(tester);

      // Biri alındı, biri alınamadı (satırı düştü), biri hâlâ geliyor: ilerleme görünür, eklenemez.
      expect(names(tester), ['Vida kutusu', 'IMG_0042']);
      expect(find.text(s.burstImporting(2, 3)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text(s.burstTakeMore), findsNothing, reason: 'galeriden gelindi: kamera düğmesi yok');
      expect(addButton(tester).onPressed, isNull, reason: 'alma sürerken eklenmez');

      hold['img']!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text(s.burstImportFailed(1)), findsOneWidget);
      expect(addButton(tester).onPressed, isNotNull);

      await tester.tap(find.text(s.burstMoreFromGallery));
      await tester.pumpAndSettle();
      expect(names(tester), ['Vida kutusu', 'IMG_0042', 'Pense']);
      await tester.enterText(fields.at(1), 'Kablo');

      // Kaydederken hazırlık (ton, iz) ilerlemesi görünür; sonra hepsi tek yazımla girer.
      await tester.tap(find.text(s.burstAddItems(3)));
      await tester.pump();
      expect(find.text(s.burstPreparing(0, 3)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await settleFiles(tester, () => find.byType(BurstAddPage).evaluate().isEmpty);
      expect(find.byType(BurstAddPage), findsNothing);
      final added = store.childrenOf(Roots.home);
      expect(added.map(store.nameOf), ['Vida kutusu', 'Kablo', 'Pense'], reason: 'seçim sırasıyla');
      for (final n in added) {
        expect(AppPaths.imageFile(n.imagePath), isNotNull, reason: 'fotoğraf envanterin klasörüne alındı');
        expect(n.imageSig, isNotNull, reason: 'görüntüyle arama izi hazırlandı');
      }
      final images = Directory(p.join(AppPaths.docsDir, 'images')).listSync();
      expect(images, hasLength(3), reason: 'alınamayan fotoğraftan dosya kalmaz');
      expect(find.text(s.burstAdded(3, s.home)), findsOneWidget);
      await settleIo(tester);
    });

    testWidgets('galeriden alma sürerken vazgeçilirse sonradan gelen fotoğraf da silinir', (tester) async {
      await boot(tester);
      final hold = {'pense': Completer<void>()};
      await fakeGallery(tester, [
        [('vida', 'Vida kutusu.jpg'), ('pense', 'Pense.jpg')],
      ], hold: hold);
      await openGallery(tester);
      expect(names(tester), ['Vida kutusu', 'Pense']);
      final images = Directory(p.join(AppPaths.docsDir, 'images'));
      expect(images.listSync(), hasLength(1));

      await tester.tap(find.byTooltip(s.back));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.burstDiscard));
      await tester.pumpAndSettle();
      expect(find.byType(BurstAddPage), findsNothing);
      hold['pense']!.complete();
      await tester.pumpAndSettle();
      expect(images.listSync(), isEmpty, reason: 'alınmış olan da sonradan gelen de silindi');
      expect(store.childrenOf(Roots.home), isEmpty);
    });
  });

  group('bakım', () {
    testWidgets('düzenleyicide döngü kurulur; odak katmanında "Bakım yapıldı" tek dokunuş, geri alınır', (tester) async {
      await boot(tester);
      final (_, pil) = await boxWithBattery(tester);
      await tester.tap(find.text('Pil'));
      await tester.pumpAndSettle();
      expect(find.text(s.maintenanceDone), findsNothing, reason: 'bakımı olmayan eşyada yok');
      await tester.tap(find.byTooltip(s.edit).last);
      await tester.pumpAndSettle();
      await openSection(tester, s.serviceSection);

      // Döngü: hızlı seçimden "3 ay". Son bakım bugün sayılır, sonraki üç ay sonra.
      await tester.ensureVisible(find.text(s.serviceCycle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.serviceCycle));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, '3 ay'));
      await tester.pumpAndSettle();
      final today = dateOnly(DateTime.now());
      final next = const TimeSpan(3, SpanUnit.month).addTo(today);
      expect(find.textContaining(s.nextServiceOn(s.formatDate(next))), findsOneWidget);

      await tester.ensureVisible(find.text(s.serviceTaskTitle));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.serviceTaskTitle));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Yağla');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.save).first);
      await settleIo(tester);
      final saved = store.byId(pil)!;
      expect(saved.serviceEvery, '3m');
      expect(saved.serviceTask, 'Yağla');
      expect(saved.servicedAt, today);
      expect(saved.serviceLog, isEmpty, reason: 'döngü kurmak bakım yapmak değil');

      // Odak katmanı: döngü ve sonraki bakım; tek dokunuşla yapıldı, bildirimden geri alınır.
      await tester.tap(find.text('Pil'));
      await tester.pumpAndSettle();
      expect(find.text('3 ayda bir · Yağla'), findsOneWidget);
      await tester.tap(find.text(s.maintenanceDone));
      await settleIo(tester);
      expect(store.byId(pil)!.serviceLog, [ServiceEntry(today)]);
      expect(find.text(s.maintainedWithNext('Pil', s.formatDate(next))), findsOneWidget);
      await tester.tap(find.text(s.undo));
      await settleIo(tester);
      expect(store.byId(pil)!.serviceLog, isEmpty);
      expect(store.byId(pil)!.servicedAt, today);
    });

    testWidgets('bakımı gelen "Bugün" şeridinde ve Tarihi yaklaşanlar\'da; oradan da yapıldı denir', (tester) async {
      await boot(tester);
      final today = dateOnly(DateTime.now());
      late String klima;
      await tester.runAsync(() async {
        final d = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
              name: 'Klima',
              serviceEvery: '1m',
              serviceTask: 'Filtreyi temizle',
              servicedAt: today.subtract(const Duration(days: 40)),
            );
        await store.commit(d);
        klima = d.id;
        await store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item)
            .copyWith(name: 'Bisiklet', serviceEvery: '6m', servicedAt: today));
      });
      await tester.pumpAndSettle();

      final strip = find.descendant(of: find.byType(TodayStrip), matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(find.text(s.todayService(1)), 120, scrollable: strip);
      await tester.tap(find.text(s.todayService(1)));
      await tester.pumpAndSettle();
      expect(find.byType(DatesPage), findsOneWidget);
      expect(find.text(s.upper(s.serviceDueSection)), findsOneWidget);
      expect(find.text(s.upper(s.serviceScheduleSection)), findsOneWidget);
      expect(find.textContaining('Filtreyi temizle'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.widgetWithText(RecordTile, 'Klima'),
        matching: find.byTooltip(s.maintenanceDone),
      ));
      await settleIo(tester);
      expect(store.byId(klima)!.servicedAt, today);
      expect(store.serviceDue, isEmpty);
      expect(find.text(s.upper(s.serviceDueSection)), findsNothing, reason: 'yapılınca takvime geçer');
    });

    testWidgets('geçmişe elle kayıt: gün ve not; yeniyse son bakım olur; yanlış kayıt silinir', (tester) async {
      await boot(tester);
      final today = dateOnly(DateTime.now());
      late String kombi;
      await tester.runAsync(() async {
        final d = store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(
              name: 'Kombi',
              serviceEvery: '1y',
              servicedAt: today.subtract(const Duration(days: 100)),
            );
        await store.commit(d);
        kombi = d.id;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kombi'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.edit).last);
      await tester.pumpAndSettle();

      // Bakımı olan kayıtta bölüm açık gelir. Gün bugün önerilir, sonra not.
      await tester.ensureVisible(find.text(s.serviceAddEntry));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.serviceAddEntry));
      await tester.pumpAndSettle();
      final picker = find.byType(DatePickerDialog);
      expect(picker, findsOneWidget);
      await tester.tap(find.text(MaterialLocalizations.of(tester.element(picker)).okButtonLabel));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Servis: Ahmet usta',
      );
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(s.save)));
      await tester.pumpAndSettle();
      expect(find.text('Servis: Ahmet usta'), findsOneWidget);
      await tester.tap(find.text(s.save).first);
      await settleIo(tester);
      final saved = store.byId(kombi)!;
      expect(saved.serviceLog, [ServiceEntry(today, 'Servis: Ahmet usta')]);
      expect(saved.servicedAt, today, reason: 'son bakımdan yeni');

      // Odak katmanında son bakım notuyla; yanlış kayıt düzenleyicide silinir.
      await tester.tap(find.text('Kombi'));
      await tester.pumpAndSettle();
      expect(find.text('${s.lastService}: ${s.formatDate(today)} · Servis: Ahmet usta'), findsOneWidget);
      await tester.tap(find.byTooltip(s.edit).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip(s.serviceRemoveEntry));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.serviceRemoveEntry));
      await tester.pumpAndSettle();
      expect(find.text(s.serviceHistoryEmpty), findsOneWidget);
      await tester.tap(find.text(s.save).first);
      await settleIo(tester);
      expect(store.byId(kombi)!.serviceLog, isEmpty);
    });
  });

  group('sayım', () {
    /// Sol menüden "Sayım / denetim"; açılan pencerede [scope] seçilir.
    Future<void> startAudit(WidgetTester tester, String scope) async {
      await tester.tap(find.byTooltip(s.menu));
      await tester.pumpAndSettle();
      final menu = find.descendant(of: find.byType(Drawer), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text(s.auditInventory), 200, scrollable: menu);
      await tester.tap(find.text(s.auditInventory));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, scope));
      await tester.pumpAndSettle();
    }

    testWidgets('menüden klasör seçilerek başlar: seçici taşıma değil seçim kipinde, kapsam o klasör', (tester) async {
      await boot(tester);
      await boxWithBattery(tester, inside: true);
      await tester.runAsync(
        () => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap')),
      );
      await tester.pumpAndSettle();

      // Seçici boş listeyle taşıma kipinde açılıp çöküyordu ("Bad state: No element"), ekran boş kalıyordu.
      await startAudit(tester, s.container);
      expect(tester.takeException(), isNull);
      final sheet = find.byType(DraggableScrollableSheet);
      expect(find.descendant(of: sheet, matching: find.text(s.auditPickFolder)), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text(s.moveHere)), findsNothing);
      await tester.tap(find.descendant(of: sheet, matching: find.text('Kutu')));
      await tester.pumpAndSettle();
      expect(find.text(s.noFoldersInside), findsOneWidget);
      await tester.tap(find.text(s.auditCountHere));
      await tester.pumpAndSettle();

      expect(find.byType(AuditPage), findsOneWidget);
      final page = find.byType(AuditPage);
      expect(find.descendant(of: page, matching: find.text('Pil')), findsOneWidget);
      expect(find.descendant(of: page, matching: find.text('Matkap')), findsNothing, reason: 'klasörün dışında');
      expect(find.text(s.auditItemProgress(0, 1)), findsOneWidget);
      await tester.tap(find.text(s.verifyAction));
      await tester.pumpAndSettle();
      expect(find.text(s.auditItemProgress(1, 1)), findsOneWidget);

      await tester.tap(find.byTooltip(s.finishAudit));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.auditApplyAndFinish));
      await settleIo(tester);
      expect(find.byType(AuditPage), findsNothing);
      expect(find.text(s.auditCompletedNotice), findsOneWidget);
    });

    testWidgets('"Tüm envanter" bütün eşyaları sayar', (tester) async {
      await boot(tester);
      await boxWithBattery(tester, inside: true);
      await tester.runAsync(
        () => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Matkap')),
      );
      await tester.pumpAndSettle();
      await startAudit(tester, s.auditEntireInventory);
      final page = find.byType(AuditPage);
      expect(page, findsOneWidget);
      expect(find.descendant(of: page, matching: find.text('Pil')), findsOneWidget);
      expect(find.descendant(of: page, matching: find.text('Matkap')), findsOneWidget);
      expect(find.text(s.auditItemProgress(0, 2)), findsOneWidget);
    });

    /// Sayımı [folder] için doğrudan açar; [scan] okutmanın yerine geçer (kamerasız).
    Future<void> openAudit(WidgetTester tester, String folder, String name, {ScannedCode? scan}) async {
      unawaited(Navigator.of(tester.element(find.byType(HomeScreen))).push(MaterialPageRoute<void>(
        builder: (_) => AuditPage(
          containerId: folder,
          containerName: name,
          scan: scan == null ? null : () async => scan,
        ),
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('tanınmayan barkoddan eklenen eşya sayılmış girer; o ana kadarki sayım sıfırlanmaz', (tester) async {
      await boot(tester);
      final (kutu, _) = await boxWithBattery(tester, inside: true);
      await openAudit(tester, kutu, 'Kutu', scan: const ScannedCode.barcode('5901234123457'));
      await tester.tap(find.text(s.verifyAction).first);
      await tester.pumpAndSettle();
      expect(find.text(s.auditItemProgress(1, 1)), findsOneWidget);

      await tester.tap(find.byTooltip(s.scanBarcode));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.newItemWithBarcode));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(NodeCard), matching: find.byType(TextField)), 'Vida');
      await tester.tap(find.text(s.save));
      await settleIo(tester);
      expect(store.byBarcode('5901234123457').single.name, 'Vida');
      // Liste baştan kuruluyordu: Pil de sayılmamış görünüyordu (0 / 2).
      expect(find.text(s.auditItemProgress(2, 2)), findsOneWidget);
    });

    testWidgets('mutabakat adedi paket kuralıyla, kaydın o anki haline yazar', (tester) async {
      await boot(tester);
      late String dolap;
      late String sut;
      final early = DateTime(2026, 11, 5);
      final later = DateTime(2026, 11, 12);
      await tester.runAsync(() async {
        final d = store.draft(parentId: Roots.home, kind: NodeKind.container).copyWith(name: 'Dolap');
        await store.commit(d);
        dolap = d.id;
        final n = store.draft(parentId: d.id, kind: NodeKind.item).copyWith(name: 'Süt');
        await store.commit(withLots(n, [Lot(2, early), Lot(4, later)]));
        sut = n.id;
      });
      await tester.pumpAndSettle();
      expect(store.byId(sut)!.quantity, 6);

      await openAudit(tester, dolap, 'Dolap');
      // Önce hepsi doğrulanır (6), sonra üç tane eksik sayılır: adım düğmeleri sayılan satırda çıkar.
      await tester.tap(find.text(s.verifyAction));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.remove_rounded));
        await tester.pumpAndSettle();
      }
      // Sayım sürerken kayıt başka yerden değişir (ör. ortak kullanımda karşıdan).
      await tester.runAsync(() => store.commit(store.byId(sut)!.copyWith(name: 'Süt (açık)')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.finishAudit));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.auditApplyAndFinish));
      await settleIo(tester);

      final n = store.byId(sut)!;
      expect(n.quantity, 3);
      expect(n.lots, isEmpty, reason: 'en eski paket bitti, tek paket kaldı');
      expect(n.expiresAt, later);
      expect(n.name, 'Süt (açık)', reason: 'sayımın başındaki kopya yazılmadı');
    });
  });

  group('klasörler arası gezinme', () {
    /// İç içe dört klasör (Ev / Oda / Dolap / Kutu), ana ekranda ya da çekmecede; kimlikleri sırayla.
    Future<List<String>> nest(WidgetTester tester, {String root = Roots.home}) async {
      final ids = <String>[];
      await tester.runAsync(() async {
        var parent = root;
        for (final name in ['Ev', 'Oda', 'Dolap', 'Kutu']) {
          final folder = store.draft(parentId: parent, kind: NodeKind.container).copyWith(name: name);
          await store.commit(folder);
          ids.add(folder.id);
          parent = folder.id;
        }
      });
      await tester.pumpAndSettle();
      return ids;
    }

    /// Kartlara dokunarak [names] sırasıyla içeri iner.
    Future<void> walkIn(WidgetTester tester, [List<String> names = const ['Ev', 'Oda', 'Dolap', 'Kutu']]) async {
      for (final name in names) {
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }
    }

    /// Arama, QR ve sık kullanılanlar klasörü, bulunulan ekranın üstüne tek başına açar.
    Future<void> openAlone(WidgetTester tester, String id) async {
      unawaited(Navigator.of(tester.element(find.byType(HomeScreen))).push(
        MaterialPageRoute<void>(builder: (_) => ContainerScreen(containerId: id)),
      ));
      await tester.pumpAndSettle();
    }

    Finder screens() => find.byType(ContainerScreen, skipOffstage: false);
    Finder screenOf(String id) =>
        find.byWidgetPredicate((w) => w is ContainerScreen && w.containerId == id, skipOffstage: false);
    Finder heading(String name) => find.descendant(of: find.byType(ShellHeader), matching: find.text(name));
    Finder pathItem(String label) =>
        find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text(label));
    /// Yol menüsünü açar; seviyelerin değerlerini döner (sondaki "Başka klasöre git…" değersiz).
    Future<List<String>> openPath(WidgetTester tester) async {
      await tester.tap(find.byTooltip(s.parentFolders));
      await tester.pumpAndSettle();
      final items = tester.widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>));
      return [for (final item in items) ?item.value];
    }

    Future<String> folder(WidgetTester tester, String name, String parent) async {
      final node = store.draft(parentId: parent, kind: NodeKind.container).copyWith(name: name);
      await tester.runAsync(() => store.commit(node));
      await tester.pumpAndSettle();
      return node.id;
    }

    /// Klasör ağacındaki (alttan açılan pencere) yazı.
    Finder inTree(String text) => find.descendant(of: find.byType(BottomSheet), matching: find.text(text));
    Future<void> openTree(WidgetTester tester) async {
      await openPath(tester);
      await tester.tap(find.text(s.otherFolder));
      await tester.pumpAndSettle();
    }

    /// Ağaçta [names]'e sırayla dokunur (klasör satırı ya da yoldaki parça).
    Future<void> browse(WidgetTester tester, List<String> names) async {
      for (final name in names) {
        await tester.tap(inTree(name));
        await tester.pumpAndSettle();
      }
    }

    (String, String?) top(WidgetTester tester) {
      final screen = tester.widget<ContainerScreen>(find.byType(ContainerScreen));
      return (screen.containerId, screen.highlightId);
    }

    testWidgets('başlıktaki ada dokununca üst seviyeler kökten sıralanır; seçilene doğrudan gidilir', (tester) async {
      await boot(tester);
      final ids = await nest(tester);
      expect(find.byTooltip(s.parentFolders), findsNothing, reason: 'ana ekranın üstü yok');
      await walkIn(tester);
      expect(screens(), findsNWidgets(4));
      expect(heading('Kutu'), findsOneWidget);

      expect(await openPath(tester), [Roots.home, ...ids], reason: 'ana ekran, üç üst klasör, en altta bulunulan');
      await tester.tap(pathItem('Oda'));
      await settleIo(tester);
      expect(screens(), findsNWidgets(2), reason: 'üstteki iki ekran kapandı, yenisi açılmadı');
      expect(heading('Oda'), findsOneWidget);
      expect(store.settings.lastLevel, ids[1], reason: 'uygulama yeniden açılınca burada başlar');

      // Geri tuşu oradan yine birer birer yukarı çıkar.
      await tester.tap(find.byTooltip(s.back));
      await tester.pumpAndSettle();
      expect(heading('Ev'), findsOneWidget);
      await openPath(tester);
      await tester.tap(pathItem(s.home));
      await settleIo(tester);
      expect(screens(), findsNothing);
      expect(store.settings.lastLevel, isNull);
    });

    testWidgets('tek başına açılan klasörde üst klasöre gidilince ana ekrandan oraya kadar açılır', (tester) async {
      await boot(tester);
      final ids = await nest(tester);
      await openAlone(tester, ids[3]);
      expect(screens(), findsOneWidget);

      await openPath(tester);
      await tester.tap(pathItem('Oda'));
      await settleIo(tester);
      expect(screens(), findsNWidgets(2), reason: 'Ev ve Oda');
      expect(top(tester), (ids[1], ids[2]), reason: 'gelinen yoldaki Dolap öne gelir');
      await tester.tap(find.byTooltip(s.back));
      await tester.pumpAndSettle();
      expect(top(tester), (ids[0], ids[1]));
      await tester.tap(find.byTooltip(s.back));
      await settleIo(tester);
      expect(screens(), findsNothing);
    });

    testWidgets('aradaki başka sayfalar da kapanır: klasörden aramaya, aramadan klasöre', (tester) async {
      await boot(tester);
      final ids = await nest(tester);
      await walkIn(tester, ['Ev']);
      final navigator = Navigator.of(tester.element(find.byType(ContainerScreen)));
      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const SearchPage())));
      await tester.pumpAndSettle();
      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => ContainerScreen(containerId: ids[3]))));
      await tester.pumpAndSettle();

      await openPath(tester);
      await tester.tap(pathItem('Ev'));
      await settleIo(tester);
      expect(find.byType(SearchPage, skipOffstage: false), findsNothing);
      expect(screens(), findsOneWidget);
      expect(heading('Ev'), findsOneWidget);
    });

    testWidgets('geri okuna basılı tutunca doğrudan ana ekrana dönülür', (tester) async {
      await boot(tester);
      await nest(tester);
      await walkIn(tester);
      await tester.longPress(find.byTooltip(s.back));
      await settleIo(tester);
      expect(screens(), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(store.settings.lastLevel, isNull);
    });

    testWidgets('çekmecedeki klasörün yolunda çekmece de var; seçilince ana ekranda çekmece açılır', (tester) async {
      await boot(tester);
      final ids = await nest(tester, root: Roots.drawer);
      await openAlone(tester, ids[1]);
      expect(await openPath(tester), [Roots.home, Roots.drawer, ids[0], ids[1]]);
      await tester.tap(pathItem(s.drawer));
      await settleIo(tester);
      expect(screens(), findsNothing);
      expect(find.text('Ev'), findsOneWidget, reason: 'çekmece paneli açık, klasör orada');
    });

    testWidgets('sürüklerken yerinde inilen klasörlerde de yol menüsü ve uzun basma çalışır', (tester) async {
      await boot(tester);
      final ids = await nest(tester);
      await tester.runAsync(
        () => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil')),
      );
      await tester.pumpAndSettle();
      // Pil'i al; Ev'in, sonra Oda'nın üzerinde bekle: ekran açılmadan yerinde içine inilir.
      final g = await pickUp(tester, 'Pil');
      for (final name in ['Ev', 'Oda']) {
        await g.moveTo(tester.getCenter(find.ancestor(of: find.text(name), matching: find.byType(NodeCardTile)).first));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pump();
      }
      await g.moveTo(tester.getCenter(find.text(s.cancelDrag)));
      await tester.pump();
      await g.up();
      await settleIo(tester);
      expect(screens(), findsNothing, reason: 'ana ekranın kabuğu yerinde indi');
      expect(heading('Oda'), findsOneWidget);

      expect(await openPath(tester), [Roots.home, ids[0], ids[1]]);
      await tester.tap(pathItem('Ev'));
      await settleIo(tester);
      expect(heading('Ev'), findsOneWidget);
      await tester.longPress(find.byTooltip(s.back));
      await settleIo(tester);
      expect(find.byTooltip(s.back), findsNothing, reason: 'ana ekranın kendisi');
      expect(find.byTooltip(s.menu), findsOneWidget);
    });

    testWidgets('üstü çöpe giden klasörün ekranı kapanır; içindekinin QR\'ı açılmaz', (tester) async {
      await boot(tester);
      final ids = await nest(tester);
      // Dolap tek başına açık (aramadan, sık kullanılanlardan): Ev'in ekranı yığında yok, kendi kapanıp
      // üstündekileri de kapatamaz.
      await openAlone(tester, ids[2]);
      expect(screens(), findsOneWidget);
      // Başka telefondan Ev çöpe atıldı: yalnızca Ev işaretli, Oda ve Dolap değil.
      await tester.runAsync(() => store.moveToTrash(ids[0]));
      await settleIo(tester);
      expect(screens(), findsNothing);

      final context = tester.element(find.byType(NodeListView).last);
      unawaited(openScanned(context, ScannedCode(id: ids[3], isContainer: true)));
      await tester.pumpAndSettle();
      expect(screens(), findsNothing);
      expect(find.text(s.qrRecordMissing), findsOneWidget);
    });

    testWidgets('yatay ekranın tek satırlık başlığında da ada dokununca yol açılır', (tester) async {
      await boot(tester, size: const Size(860, 400));
      await nest(tester);
      await walkIn(tester, ['Ev', 'Oda']);
      expect(await openPath(tester), hasLength(3));
      await tester.tap(pathItem(s.home));
      await settleIo(tester);
      expect(screens(), findsNothing);
    });

    testWidgets('"Başka klasöre git": ağaç bulunulan klasörde açılır, başka daldaki klasöre geçilir', (tester) async {
      await boot(tester);
      final ids = await nest(tester);
      final garage = await folder(tester, 'Garaj', Roots.home);
      final shelf = await folder(tester, 'Raf', garage);
      await walkIn(tester);

      await openTree(tester);
      expect(find.text(s.whichFolderToGo), findsOneWidget);
      expect(inTree(s.noFoldersWhereYouAre), findsOneWidget, reason: 'Kutu\'nun içinde açıldı');
      await tester.tap(inTree(s.youAreHere));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'bulunulan klasöre gidilmez');

      await tester.tap(find.widgetWithText(ChoiceChip, s.home));
      await tester.pumpAndSettle();
      await browse(tester, ['Garaj', 'Raf']);
      await tester.tap(inTree(s.goHere));
      // Geçişin ortasında: Kutu yerinde durur, Garaj görünmeden açılır; görünen tek şey Raf'ın açılışı.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(screenOf(ids[3]), findsOneWidget);
      final under = find.ancestor(of: screenOf(garage), matching: find.byType(Opacity)).first;
      expect(tester.widget<Opacity>(under).opacity, 0);
      await settleIo(tester);
      expect(find.byType(BottomSheet), findsNothing);
      expect(screens(), findsNWidgets(2), reason: 'Ev, Oda, Dolap, Kutu kapandı; Garaj ve Raf açıldı');
      expect(top(tester), (shelf, null));
      expect(store.settings.lastLevel, shelf);

      // Geri tuşu yeni yolda yukarı çıkar: Garaj'da Raf öne gelir, sonra ana ekran.
      await tester.tap(find.byTooltip(s.back));
      await tester.pumpAndSettle();
      expect(top(tester), (garage, shelf));
      await tester.tap(find.byTooltip(s.back));
      await settleIo(tester);
      expect(screens(), findsNothing);
    });

    testWidgets('ağaçtan aynı daldaki bir klasöre geçilince ortak üst klasörlerin ekranları kalır', (tester) async {
      await boot(tester);
      final ids = await nest(tester);
      final shelf = await folder(tester, 'Raf', ids[1]);
      await walkIn(tester);

      await openTree(tester);
      await browse(tester, ['Dolap']);
      expect(inTree(s.youAreHere), findsOneWidget, reason: 'Kutu satırında: şu an orada');
      await browse(tester, ['Oda', 'Raf']);
      await tester.tap(inTree(s.goHere));
      await settleIo(tester);
      expect(screens(), findsNWidgets(3), reason: 'Ev ve Oda kaldı, üstüne Raf açıldı');
      expect(top(tester), (shelf, null));

      await tester.tap(find.byTooltip(s.back));
      await settleIo(tester);
      expect(top(tester), (ids[1], null), reason: 'kartla açılan Oda ekranının kendisi, yeniden açılmadı');
    });

    testWidgets('yerinde inilmiş ana ekrandan ağaçla gidilince son açık yer gidilen klasördür', (tester) async {
      await boot(tester);
      await nest(tester);
      final garage = await folder(tester, 'Garaj', Roots.home);
      final shelf = await folder(tester, 'Raf', garage);
      await tester.runAsync(
        () => store.commit(store.draft(parentId: Roots.home, kind: NodeKind.item).copyWith(name: 'Pil')),
      );
      await tester.pumpAndSettle();
      // Pil'i al, Ev'in üzerinde bekle: ekran açılmadan yerinde içine inilir.
      final g = await pickUp(tester, 'Pil');
      await g.moveTo(tester.getCenter(find.ancestor(of: find.text('Ev'), matching: find.byType(NodeCardTile)).first));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump();
      await g.moveTo(tester.getCenter(find.text(s.cancelDrag)));
      await tester.pump();
      await g.up();
      await settleIo(tester);
      expect(screens(), findsNothing);
      expect(heading('Ev'), findsOneWidget);

      await openTree(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, s.home));
      await tester.pumpAndSettle();
      await browse(tester, ['Garaj', 'Raf']);
      await tester.tap(inTree(s.goHere));
      await settleIo(tester);
      expect(screens(), findsNWidgets(2));
      expect(top(tester), (shelf, null));
      expect(store.settings.lastLevel, shelf, reason: 'örtülen ana ekran kırpılan seviyesini sonradan yazmadı');

      await tester.tap(find.byTooltip(s.back));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(s.back));
      await settleIo(tester);
      expect(screens(), findsNothing);
      expect(heading('Ev'), findsNothing, reason: 'ana ekran yerinde inilen Ev\'den çıkmıştı');
      expect(store.settings.lastLevel, isNull);
    });
  });
}
