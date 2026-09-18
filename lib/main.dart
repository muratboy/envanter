import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'core/app_paths.dart';
import 'core/theme.dart';
import 'data/library.dart';
import 'services/background.dart';
import 'services/platform_bridge.dart';
import 'state/inventory_host.dart';
import 'sync/clock.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Uygulama kapalıyken arka planda açılmış bir iş varsa veritabanını bıraksın.
  await PlatformBridge.waitBackgroundIdle();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await AppPaths.init();
  // Bu cihazdaki envanterler ve hangisinin açık olduğu; kişisel ayarlar da orada.
  final library = await InventoryLibrary.load(rootDir: AppPaths.rootDir, dbDir: await getDatabasesPath());
  InventoryLibrary.current = library;
  // Dikey ve yatay (yatayda ayrı düzen); kişi "Ekranı döndür"ü kapattıysa telefonda hep dikey.
  await applyOrientation(rotate: library.global['rotate_screen'] != '0');
  // Eşitleme damgalarının saati: otomatik değilse öğrenilmiş düzeltmesiyle.
  SyncClock.restore(auto: await PlatformBridge.autoTime());
  final host = InventoryHost(library);
  // Açılışı bekletmeden ekranı gösterip veriyi arkadan yüklüyoruz (bkz. InventoryHost).
  await host.start();
  // Uygulama yaşarken (arka planda da olsa) Android'in arka plan işi burada çalışır.
  PlatformBridge.onBackgroundTask = (task) => BackgroundWork.run(host, task);
  PlatformBridge.listen();
  runApp(EnvanterRoot(host: host));
}

/// Uygulama kapalıyken Android'in ayrı motorda çalıştırdığı iş (`BackgroundJob.kt`).
@pragma('vm:entry-point')
Future<void> backgroundMain(List<String> args) => BackgroundWork.headless(args.isEmpty ? 'sync' : args.first);
