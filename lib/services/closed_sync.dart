import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';

import '../core/app_paths.dart';
import '../core/strings.dart';
import '../data/database.dart';
import '../data/library.dart';
import '../state/inventory_host.dart';
import '../state/inventory_store.dart';
import '../sync/clock.dart';
import '../sync/sharing_config.dart';
import '../sync/sharing_service.dart';
import 'platform_bridge.dart';

/// Yalıtımın başında çalışan hazırlık (testler veritabanı sürücüsünü kurar).
typedef VisitSetup = FutureOr<void> Function(Object? arg);

/// Ziyaret edilen envanterin ortak kullanımını kuran işlev (testler kendi ağ
/// ayarlarıyla kurar). Yalıtıma gittiği için üst düzey bir işlev olmalı.
typedef VisitSharing = SharingService Function(InventoryStore store, String Function() displayName);

/// Paylaşılan ama **açık olmayan** envanterlerin arka planda eşitlenmesi.
///
/// Uygulama aynı anda tek envanterin veritabanını açık tutar; "Ev"i eşinle
/// paylaşıp günlerce "Atölye"yi açık tutarsan "Ev" hiç eşitlenmiyor, alışveriş
/// listesi ve bildirimleri de eskiyordu. Burada kapalı envanterler sırayla,
/// **ayrı bir yalıtımda** açılır, kısa bir eşitleme turu yapılır ve kapatılır.
///
/// Neden ayrı yalıtım: veritabanı ([AppDatabase.instance]) ve dosya klasörü
/// ([AppPaths]) uygulamada tekildir. Aynı yalıtımda başka envantere geçmek
/// açık envanterin arayüzünü baştan kurar (yarım kalmış bir düzenleme kaybolur)
/// ya da yazımları yanlış veritabanına düşürür. Yalıtımın tekilleri kendine
/// aittir: açık envantere hiç dokunulmaz.
///
/// Kurallar:
/// - Yalnızca uygulama **önde değilken** çalışır (arka plan işi çağırır); öne
///   gelince durdurulur ([stop]). Önde iken açık envanterin ağı çalışır; aynı
///   cihazdan iki envanterin birden duyurulması öteki cihazları şaşırtırdı.
/// - Kütüphane dosyasının sahibi uygulamadır. Yalıtım onu **salt okunur** açar
///   ve her envanterin yeni özetini (kayıt sayısı, alışveriş listesi, bildirim
///   satırları, onay bekleyenler) buraya gönderir; dosyaya burası yazar.
/// - Bir envantere geçmeden ya da onu silmeden önce [stop] beklenir: aynı
///   veritabanı iki yerden açılmasın.
/// - Otomatik yedek, tarih bildirimi kurulumu, katılma isteklerinin onayı gibi
///   arayüz ya da tekil servis isteyen işler burada yapılmaz; envanter
///   açılınca yapılır.
class ClosedSync {
  /// Envanter başına eşitleme süresi (ağda kimse yoksa bu kadar beklenir).
  static const window = Duration(seconds: 20);

  /// Bir turda en çok bu kadar envanter (arka plan işinin süresi sınırlı).
  static const maxInventories = 5;

  static Future<int>? _running;
  static SendPort? _control;
  static bool _stopping = false;

  static bool get busy => _running != null;

  /// Eşitlenecekler: açık olmayan ve (en son kapandığında) paylaşılan envanterler.
  static List<InventoryEntry> targets(InventoryLibrary library, String? openId) => [
        for (final e in library.entries)
          if (e.id != openId && e.shared) e,
      ].take(maxInventories).toList();

  /// Kapalı envanterleri sırayla eşitler; kaç envanterin özetinin yenilendiğini
  /// döner. Ayar kapalıysa ya da eşitlenecek envanter yoksa hiçbir şey yapmaz.
  /// [platform]: yalıtımda yerel kanallar (sqflite, çoklu yayın kilidi)
  /// kullanılacak mı; testlerde yok.
  static Future<int> run(
    InventoryHost host, {
    Duration window = ClosedSync.window,
    bool platform = true,
    VisitSetup? setup,
    Object? setupArg,
    VisitSharing? makeSharing,
  }) {
    final running = _running;
    if (running != null) return running;
    final next = _run(host, window, platform, setup, setupArg, makeSharing);
    _running = next;
    return next.whenComplete(() {
      _running = null;
      _control = null;
      _stopping = false;
    });
  }

  /// Süren eşitlemeyi bitirir: yalıtım ağı durdurur, veritabanını kapatır.
  /// Bitene kadar bekler.
  static Future<void> stop() async {
    final running = _running;
    if (running == null) return;
    _stopping = true;
    _control?.send('stop');
    try {
      await running;
    } on Object {
      // Yarıda kalan tur: bir dahakine yeniden denenir.
    }
  }

  static Future<int> _run(
    InventoryHost host,
    Duration window,
    bool platform,
    VisitSetup? setup,
    Object? setupArg,
    VisitSharing? makeSharing,
  ) async {
    final library = host.library;
    if (library.global['sync_closed'] == '0') return 0;
    final openId = host.session.id;
    final ids = [for (final e in targets(library, openId)) e.id];
    if (ids.isEmpty) return 0;

    final port = ReceivePort();
    final done = Completer<void>();
    final writes = <Future<void>>[];
    var refreshed = 0;
    port.listen((message) {
      if (message is SendPort) {
        _control = message;
        if (_stopping) message.send('stop');
      } else if (message is Map) {
        final id = message['id'];
        final entry = InventoryEntry.fromJson(message['entry']);
        final current = id is String ? library.byId(id) : null;
        // Bu arada açılmış ya da silinmiş envanterin özeti yazılmaz.
        if (entry == null || current == null || id == host.session.id) return;
        refreshed++;
        writes.add(library.update(current.withSummaryOf(entry)).then((_) => host.summaryChanged()));
      } else if (!done.isCompleted) {
        // 'done' ya da yalıtımın çıkış haberi (null).
        done.complete();
      }
    });
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _visitMain,
        _VisitRequest(
          rootDir: library.rootDir,
          dbDir: library.dbDir,
          ids: ids,
          window: window,
          autoTime: SyncClock.trusted,
          turkish: AppStrings.systemTurkish,
          reply: port.sendPort,
          token: platform ? RootIsolateToken.instance : null,
          setup: setup,
          setupArg: setupArg,
          makeSharing: makeSharing,
        ),
        onExit: port.sendPort,
      );
      // Takılırsa: önce durması istenir, yine bitmezse yalıtım kapatılır.
      final budget = Duration(seconds: ids.length * (window.inSeconds + 15) + 10);
      await done.future.timeout(budget, onTimeout: () async {
        _control?.send('stop');
        await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
      });
    } finally {
      isolate?.kill(priority: Isolate.beforeNextEvent);
      port.close();
      await Future.wait(writes);
    }
    return refreshed;
  }
}

class _VisitRequest {
  const _VisitRequest({
    required this.rootDir,
    required this.dbDir,
    required this.ids,
    required this.window,
    required this.autoTime,
    required this.turkish,
    required this.reply,
    required this.token,
    required this.setup,
    required this.setupArg,
    required this.makeSharing,
  });

  final String rootDir;
  final String dbDir;
  final List<String> ids;
  final Duration window;
  final bool autoTime;
  final bool turkish;
  final SendPort reply;
  final RootIsolateToken? token;
  final VisitSetup? setup;
  final Object? setupArg;
  final VisitSharing? makeSharing;
}

/// Yalıtımın girişi: envanterleri sırayla açar, eşitler, özetini gönderir.
Future<void> _visitMain(_VisitRequest request) async {
  final control = ReceivePort();
  final stop = Completer<void>();
  control.listen((message) {
    if (message == 'stop' && !stop.isCompleted) stop.complete();
  });
  request.reply.send(control.sendPort);
  try {
    // Yerel kanallar (sqflite, çoklu yayın kilidi) bu yalıtımdan da kullanılabilsin.
    if (request.token case final token?) BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    await request.setup?.call(request.setupArg);
    AppStrings.systemIsTurkish = request.turkish;
    final library = await InventoryLibrary.load(rootDir: request.rootDir, dbDir: request.dbDir, readOnly: true);
    InventoryLibrary.current = library;
    SyncClock.restore(auto: request.autoTime);
    for (final id in request.ids) {
      if (stop.isCompleted) break;
      final entry = library.byId(id);
      if (entry == null) continue;
      try {
        final summary = await _visit(library, entry, request, stop.future);
        if (summary != null) request.reply.send({'id': id, 'entry': summary.toJson()});
      } on Object {
        // Açılamayan ya da eşitlenemeyen envanter atlanır; kurtarma (bozuk
        // veritabanını kenara alma) arka planda değil, envanter açılınca yapılır.
      }
    }
  } finally {
    control.close();
    request.reply.send('done');
  }
}

/// Bir envanteri açar, paylaşılıyorsa kısa bir eşitleme turu yapar, kapatır.
/// Yeni özetini döner; paylaşılmıyorsa (bu arada ayrılmış) yine özet döner ki
/// "paylaşılıyor" bilgisi düzelsin.
Future<InventoryEntry?> _visit(
  InventoryLibrary library,
  InventoryEntry entry,
  _VisitRequest request,
  Future<void> stop,
) async {
  // Bildirim satırlarındaki envanter adı ve ayarlar bu envantere göre okunur
  // (kopya salt okunur: dosyaya yazılmaz).
  library.activeId = entry.id;
  await AppDatabase.instance.openAt(library.dbPathOf(entry.id));
  try {
    AppPaths.useDirectory(library.docsOf(entry.id));
    final store = InventoryStore();
    await store.init();
    String displayName() {
      final name = store.settings.userName.trim();
      return name.isEmpty ? store.strings.user : name;
    }

    final sharing = request.makeSharing?.call(store, displayName) ??
        SharingService(
          target: store,
          configStore: MetaSharingConfigStore(),
          displayName: displayName,
          setMulticastLock: request.token == null ? null : PlatformBridge.setMulticastLock,
        );
    await sharing.load();
    InventoryHost.wire(store, sharing);
    try {
      if (sharing.config.enabled && sharing.config.isShared) {
        await Future.any([sharing.syncRound(window: request.window), stop]);
      }
    } finally {
      await sharing.shutdown();
      await store.settle();
    }
    try {
      await library.writeIndex(entry.id, store.searchIndex());
    } on Object {
      // Dizin yazılamazsa yalnızca kapalıyken arama eksik kalır.
    }
    final summary = InventoryHost.summarize(entry, store, sharing, library.labelFor(store.strings.appTitle));
    sharing.dispose();
    store.dispose();
    return summary;
  } finally {
    await AppDatabase.instance.close();
  }
}
