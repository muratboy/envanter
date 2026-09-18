import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/auto_backup.dart';
import '../services/backup_service.dart';
import '../services/platform_bridge.dart';
import '../state/inventory_host.dart';
import '../state/inventory_store.dart';

/// Yedeği dışa aktarma ve geri yükleme akışları (ayarlardan çağrılır).
class BackupFlows {
  /// "Son yedek: 12 gün önce" ya da "Henüz yedek alınmadı." Günler takvime
  /// göre sayılır: dün gece alınan yedek sabah "dün" görünür.
  static String lastBackupLabel(InventoryStore store, [DateTime? now]) {
    final s = store.strings;
    final last = store.settings.lastBackupAt;
    if (last == null) return s.neverBackedUp;
    final today = now ?? DateTime.now();
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(last.year, last.month, last.day))
        .inDays;
    return s.lastBackup(days <= 0 ? s.today : s.daysAgo(days));
  }

  /// Envanteri tek dosyaya koyar ve paylaşım penceresini açar: kullanıcı
  /// dosyayı istediği yere kaydeder ya da gönderir.
  static Future<void> export(BuildContext context) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    // Ekli bir envanterde saniyeler sürebilir: bir şeyin olduğu görülsün.
    final busy = _Busy(context, s.exporting)..show();
    try {
      final dir = await getTemporaryDirectory();
      final File file;
      try {
        file = await BackupService.export(store, into: dir, onProgress: busy.report);
      } finally {
        busy.close();
      }
      final shared = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/zip')],
          text: s.exportShareText,
        ),
      );
      messenger.hideCurrentSnackBar();
      // Pencere kapatıldıysa dosya bir yere gitmedi; yedek alınmış sayılmaz.
      // Android hedefi her zaman bildiremiyor ("unavailable"): o da sayılır.
      if (shared.status != ShareResultStatus.dismissed) await store.markBackedUp();
    } on Object catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(s.exportFailed('$e'))));
    }
  }

  /// Otomatik yedeği açar ya da klasörünü değiştirir: klasör seçilir, ilk yedek
  /// hemen yazılır (klasör gerçekten yazılabiliyor mu, hemen görülsün).
  static Future<void> chooseAutoFolder(BuildContext context) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final picked = await PlatformBridge.pickFolder();
    if (picked == null) return;
    final old = store.settings.autoBackupUri;
    if (old != null && old != picked.uri) await PlatformBridge.releaseFolder(old);
    await store.updateSettings(store.settings.copyWith(
      autoBackupUri: picked.uri,
      autoBackupFolder: picked.name,
      clearAutoBackupFailure: true,
    ));
    final ok = await AutoBackup.run(store);
    // Klasör bütün envanterlerin: açılmayanlar da hemen yedeklenebilsin.
    final host = context.mounted ? LibraryScope.read(context) : null;
    final rest = ok ? host?.unbackedEntries.length ?? 0 : 0;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text([
        ok ? s.autoBackupWritten(picked.name) : s.autoBackupFailed,
        if (rest > 0) s.unbackedInventories(rest),
      ].join(' ')),
      duration: Duration(seconds: rest > 0 ? 8 : 4),
      action: rest > 0 ? SnackBarAction(label: s.backupNow, onPressed: host!.backupAll) : null,
    ));
  }

  /// Otomatik yedek önerisinin zamanı: kapalı, daha önce önerilmedi ve
  /// envanterde kaybedilince üzülecek kadar kayıt var.
  static bool shouldOffer(InventoryStore store) =>
      !store.loading &&
      store.settings.autoBackupUri == null &&
      !store.settings.backupOffered &&
      store.visibleRecordCount >= offerAt;

  static const offerAt = 20;

  /// Bir kez sorar; cevap ne olursa olsun bir daha sormaz (ayarlarda durur).
  static Future<void> offerAuto(BuildContext context) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    await store.updateSettings(store.settings.copyWith(backupOffered: true));
    if (!context.mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.backup_rounded),
        title: Text(s.backupOfferTitle),
        content: Text(s.backupOfferBody(store.visibleRecordCount)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.notNow)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.chooseFolder)),
        ],
      ),
    );
    if (yes == true && context.mounted) await chooseAutoFolder(context);
  }

  static Future<void> disableAuto(BuildContext context) async {
    final store = InventoryScope.read(context);
    final uri = store.settings.autoBackupUri;
    if (uri != null) await PlatformBridge.releaseFolder(uri);
    await store.updateSettings(store.settings.copyWith(clearAutoBackup: true));
  }

  /// Kullanıcıya dosya seçtirir ve içindekileri bu envantere katar.
  static Future<void> import(BuildContext context) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final busy = _Busy(context, s.importing);
    // Dosya seçilir seçilmez pencere açılır: önbelleğe kopyalanması da sürebilir.
    final path = await PlatformBridge.pickFile(onCopying: busy.show);
    if (path == null) {
      busy.close();
      return;
    }
    messenger.hideCurrentSnackBar();
    busy.show();
    try {
      final BackupImport result;
      try {
        result = await BackupService.import(File(path), store, onProgress: busy.report);
      } finally {
        busy.close();
        // Önbelleğe alınan kopya artık gereksiz (büyük bir yedek yer tutmasın).
        try {
          await File(path).delete();
        } on FileSystemException {
          // Sistem önbelleği zaten temizler.
        }
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(result.total == 0 && result.photos == 0
            ? s.importNothing
            : s.importDone(result.added, result.updated, result.photos)),
        duration: const Duration(seconds: 4),
      ));
    } on BackupException catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(switch (e.problem) {
          BackupProblem.notOurs => s.importNotOurs,
          BackupProblem.newerVersion => s.importNewerVersion,
          BackupProblem.unreadable => s.importFailed,
        }),
      ));
    } on Object {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(s.importFailed)));
    }
  }
}

/// Dışa/içe aktarma sürerken kapanmayan pencere: ne yapıldığı ve ilerleme
/// çubuğu. Eskiden yalnızca kısa bir bildirim çıkıyordu; ekli büyük bir
/// envanterde uygulama donmuş gibi görünüyordu.
class _Busy {
  _Busy(BuildContext context, this.title) : _navigator = Navigator.of(context, rootNavigator: true);

  final String title;
  final NavigatorState _navigator;

  // Belirsiz (dönen) çubuk yok: 0'dan başlar, iş ilerledikçe dolar.
  final ValueNotifier<double> _progress = ValueNotifier(0);
  bool _open = false;

  void report(double value) => _progress.value = value.clamp(0.0, 1.0);

  void show() {
    if (_open || !_navigator.mounted) return;
    _open = true;
    showDialog<void>(
      context: _navigator.context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) => PopScope(
        // Geri tuşu pencereyi kapatmasın: iş sürüyor.
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 18),
              ValueListenableBuilder<double>(
                valueListenable: _progress,
                builder: (_, value, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: value, minHeight: 6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void close() {
    if (!_open) return;
    _open = false;
    if (_navigator.mounted) _navigator.pop();
  }
}
