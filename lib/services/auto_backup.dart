import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/time_span.dart';
import '../state/inventory_store.dart';
import 'backup_service.dart';
import 'date_notifier.dart';
import 'platform_bridge.dart';

/// Otomatik yedek: kullanıcının bir kez seçtiği klasöre haftada bir zip. Sunucu
/// olmadığı için en büyük risk telefonun kaybolması; hatırlatma yetmiyordu.
///
/// Arka planda zamanlayıcı yok (Android'de ayrı bir iş kurmak gerekirdi):
/// uygulama açılınca ya da öne gelince vakti geldiyse yazılır. Envanter zaten
/// uygulama açıkken değişir.
class AutoBackup {
  static const interval = Duration(days: 7);

  /// Klasörde en yeni bu kadar yedek kalır.
  static const keep = 4;

  /// Klasöre yazan; testler kendi yazıcısını verir.
  static Future<bool> Function(String uri, String path, String name, int keep) write = PlatformBridge.writeBackup;

  /// Yedek dosyasının hazırlandığı geçici klasör; testler değiştirir.
  static Future<Directory> Function() tempDir = getTemporaryDirectory;

  static bool _running = false;
  static Future<bool>? _current;

  /// Kapanmakta olan envanterin mağazası: kendiliğinden yedeği başlamaz
  /// (kapanış kendisi yazar, fotoğraf klasörü birazdan değişecek).
  static InventoryStore? closing;

  /// Süren yazım bitene kadar bekler: envanter geçişi fotoğraf klasörünü
  /// değiştirir, yarım yedek öteki envanterin fotoğraflarını almasın.
  static Future<void> settle() async {
    await _current;
  }

  /// Vakti geldiyse yedeği yazar. Açık, bir haftadır yedek alınmamış ve o
  /// arada bir şey değişmiş olmalı. Yazıldıysa true.
  static Future<bool> runIfDue(InventoryStore store, {DateTime? now}) async {
    final uri = store.settings.autoBackupUri;
    if (uri == null || _running || store.loading || identical(store, closing)) return false;
    final at = now ?? DateTime.now();
    final last = store.settings.lastBackupAt;
    if (last != null && at.difference(last) < interval) return false;
    if (last != null && store.changesSinceBackup == 0) return false;
    return run(store, now: at);
  }

  /// Yazılamadı: Ayarlar'da uyarı; telefon bildirimi de, ama günde en çok bir kez.
  static Future<void> _failed(InventoryStore store, DateTime at) async {
    final before = store.settings.autoBackupFailedAt;
    await store.updateSettings(store.settings.copyWith(autoBackupFailedAt: at));
    if (before == null || dateOnly(before) != dateOnly(at)) await DateNotifier.instance.backupFailed(store.strings);
  }

  /// Hemen yazar (klasör yeni seçildiğinde ya da elle).
  static Future<bool> run(InventoryStore store, {DateTime? now}) {
    final uri = store.settings.autoBackupUri;
    if (uri == null || _running) return Future.value(false);
    return _current = _run(store, uri, now);
  }

  static Future<bool> _run(InventoryStore store, String uri, DateTime? now) async {
    _running = true;
    File? file;
    try {
      file = await BackupService.export(store, into: await tempDir());
      final ok = await write(uri, file.path, p.basename(file.path), keep);
      final at = now ?? DateTime.now();
      if (ok) {
        // Hatırlatma da buna bakar: otomatik yedek de yedektir.
        await store.updateSettings(store.settings.copyWith(lastBackupAt: at, clearAutoBackupFailure: true));
      } else {
        await _failed(store, at);
      }
      return ok;
    } on Object {
      await _failed(store, now ?? DateTime.now());
      return false;
    } finally {
      _running = false;
      try {
        await file?.delete();
      } on Object {
        // Geçici dosya; sistem de temizler.
      }
    }
  }
}
