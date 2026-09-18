import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';

import '../core/app_paths.dart';
import '../data/library.dart';
import '../state/inventory_host.dart';
import '../sync/clock.dart';
import 'auto_backup.dart';
import 'closed_sync.dart';
import 'date_notifier.dart';
import 'pending_notice.dart';
import 'platform_bridge.dart';
import 'shopping_widget.dart';

/// Android'in ara ara çalıştırdığı iş (`BackgroundJob.kt`). İki telefonun
/// eşitlenmesi için ikisinin de uygulamayı aynı anda açık tutması gerekiyordu;
/// evde bu nadiren oluyor. Artık biri açıkken öteki arka planda eşitlenir.
///
/// - `sync` (yarım saatte bir, yalnızca Wi-Fi'de): açık envanter
///   paylaşılıyorsa kısa bir eşitleme turu. Ardından, uygulama önde değilse,
///   paylaşılan kapalı envanterler de sırayla eşitlenir ([ClosedSync]; ayarı
///   varsayılan açık). Onay bekleyen yeni değişiklik geldiyse bildirim ([PendingNotice]).
/// - `daily` (günde bir): bildirim planı ileri kayar (uygulama uzun süre
///   açılmasa da bildirimler bitmesin), vakti gelen otomatik yedek yazılır,
///   widget'ın listesi tazelenir.
class BackgroundWork {
  static const syncWindow = Duration(seconds: 40);

  /// Açık envanterle işi yapar (uygulama yaşarken onun motorunda, kapalıyken
  /// arka plan motorunda).
  static Future<void> run(InventoryHost host, String task) async {
    await host.session.ready;
    final store = host.session.store;
    if (task == 'sync') {
      await host.session.sharing.syncRound(window: syncWindow);
      // Kapalı envanterler: yalnızca uygulama önde değilken (bkz. [ClosedSync]).
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        final refreshed = await ClosedSync.run(host);
        // Kapalı envanterlerin bildirim satırları yenilendi: plan da yenilensin.
        if (refreshed > 0) await DateNotifier.instance.reschedule();
      }
      // Kullanıcı bakmıyorken onay bekleyen yeni değişiklik geldiyse haber verilir. Tur
      // sürerken uygulama öne gelmiş olabilir: o zaman arayüzdeki işaret yeter.
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await PendingNotice.check(host.library, host.session.store);
      }
    } else {
      await DateNotifier.instance.reschedule();
      await AutoBackup.runIfDue(store);
      // Otomatik yedek açık ve yedeklenmemiş kapalı envanterler varsa sırayla yedeklenir.
      if (host.unbackedEntries.isNotEmpty) {
        await host.backupAll();
      }
    }
    await ShoppingWidgetSync.instance.push();
  }

  /// Uygulama kapalıyken: ayrı motor, kendi kütüphanesi ve envanteri. Uygulama
  /// bu sırada açılırsa ([PlatformBridge.onStop]) iş yarıda bırakılır, envanter
  /// kapatılır; yeni açılan uygulama veritabanını bundan sonra açar.
  static Future<void> headless(String task) async {
    WidgetsFlutterBinding.ensureInitialized();
    final stop = Completer<void>();
    PlatformBridge.onStop = () {
      if (!stop.isCompleted) stop.complete();
    };
    PlatformBridge.listen();
    InventoryHost? host;
    try {
      await AppPaths.init();
      final library = await InventoryLibrary.load(rootDir: AppPaths.rootDir, dbDir: await getDatabasesPath());
      InventoryLibrary.current = library;
      SyncClock.restore(auto: await PlatformBridge.autoTime());
      host = InventoryHost(library);
      await host.start();
      await host.session.ready;
      final store = host.session.store;
      await DateNotifier.instance.attach(store, onOpen: () {});
      await ShoppingWidgetSync.instance.attach(store);
      await Future.any([run(host, task), stop.future]);
    } on Object {
      // Arka plan işi sessiz: bir dahaki sefere yeniden denenir.
    } finally {
      // Uygulama açılıyorsa kapalı envanterin veritabanı da bırakılsın.
      await ClosedSync.stop();
      try {
        await host?.stop();
      } on Object {
        // Kapanırken hata: motor zaten kapanacak.
      }
      await PlatformBridge.backgroundDone();
    }
  }
}
