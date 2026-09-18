import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'data/node.dart';
import 'services/auto_backup.dart';
import 'services/closed_sync.dart';
import 'data/library.dart';
import 'services/date_notifier.dart';
import 'services/pending_notice.dart';
import 'ui/dates_page.dart';
import 'services/platform_bridge.dart';
import 'services/shopping_widget.dart';
import 'state/inventory_host.dart';
import 'state/inventory_store.dart';
import 'sync/clock.dart';
import 'sync/sharing_service.dart';
import 'ui/actions.dart';
import 'ui/backup_flows.dart';
import 'ui/container_screen.dart';
import 'ui/home_screen.dart';
import 'ui/inventories_page.dart';
import 'ui/search_page.dart';
import 'ui/shopping_page.dart';
import 'ui/shell.dart';
import 'ui/sharing/changes_page.dart';
import 'ui/sharing/sharing_host.dart';
import 'ui/sharing/sharing_scope.dart';
import 'ui/widgets/focus_overlay.dart';
import 'ui/widgets/scroll_guard.dart';

/// Envanterler arasında geçişte uygulama baştan kurulur: yeni gezgin, açılan
/// envanterin ana ekranı (ya da kaldığı klasör). Kişisel ayarlar (dil, tema)
/// envanterden bağımsız olduğu için görünüm değişmez.
class EnvanterRoot extends StatelessWidget {
  const EnvanterRoot({super.key, required this.host});

  final InventoryHost host;

  @override
  Widget build(BuildContext context) => LibraryScope(
        host: host,
        child: ListenableBuilder(
          listenable: host,
          builder: (context, _) => EnvanterApp(
            key: ValueKey(host.generation),
            store: host.session.store,
            sharing: host.session.sharing,
          ),
        ),
      );
}

class EnvanterApp extends StatefulWidget {
  const EnvanterApp({super.key, required this.store, required this.sharing});

  final InventoryStore store;
  final SharingService sharing;

  @override
  State<EnvanterApp> createState() => _EnvanterAppState();
}

class _EnvanterAppState extends State<EnvanterApp> with WidgetsBindingObserver {
  /// Katılma isteği hangi ekranda olursa olsun sorulabilsin diye.
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Açılışta hatırlanan seviye. Ana ekranın kabuğu "şu an ana ekrandayız"
  /// diye üzerine yazmadan önce, ilk çizimde alınır.
  String? _pendingLevel;
  bool _captured = false;
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    PlatformBridge.listenShortcuts(_takeShortcut);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Öne gelince: otomatik yedeğin vakti geldiyse yazılır; bildirim izni
  /// ayarlardan değişmiş olabilir, plan tazelenir.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Öne gelindi: arka planda kapalı bir envanter eşitleniyorsa bıraksın (açık
    // envanterin ağı yeniden başlıyor; kullanıcı o envantere geçmek de isteyebilir).
    if (state == AppLifecycleState.resumed) unawaited(ClosedSync.stop());
    // Onay bekleyenler bildirimi: öne gelince arayüzdeki işaret yeter, bildirim kalkar;
    // çıkarken o andaki sayılar "görüldü" diye yazılır (yalnızca sonradan gelen bildirilir).
    if (state == AppLifecycleState.resumed) unawaited(DateNotifier.instance.clearPending());
    final library = InventoryLibrary.current;
    if (state == AppLifecycleState.paused && library != null && _restored) {
      unawaited(PendingNotice.markSeen(library, widget.store));
    }
    if (state != AppLifecycleState.resumed || !_restored) return;
    // Saat ayarı arada değişmiş olabilir (otomatik saat açıldı ya da kapandı).
    PlatformBridge.autoTime().then((auto) => SyncClock.restore(auto: auto));
    AutoBackup.runIfDue(widget.store);
    _offerBackup();
    DateNotifier.instance.refreshPermission();
    DateNotifier.instance.reschedule();
  }

  /// Otomatik yedek kapalıyken envanter büyüdü: bir kez sorulur. Açılışta ya da
  /// öne gelince; kayıt eklerken araya girmesin (sürükleme de iptal olurdu).
  void _offerBackup() {
    final context = _navigatorKey.currentContext;
    if (context == null || !BackupFlows.shouldOffer(widget.store)) return;
    BackupFlows.offerAuto(context);
  }

  /// Bildirime dokunuldu: tarihi yaklaşanlar, en üstteki ekranın üstünde.
  void _openDates() {
    final navigator = _navigatorKey.currentState;
    navigator?.push(MaterialPageRoute<void>(builder: (_) => const DatesPage()));
  }

  /// Onay bekleyenler bildirimine dokunuldu. Tek envanterse onun değişiklikleri (kapalıysa
  /// önce açılır), birkaç envanterse işaretlerin göründüğü envanter listesi.
  void _openChanges(String? inventoryId) {
    final at = _navigatorKey.currentContext;
    if (at == null) return;
    final host = LibraryScope.read(at);
    final navigator = Navigator.of(at);
    if (host == null || inventoryId == host.library.activeId) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => const ChangesPage()));
    } else if (inventoryId != null && host.library.byId(inventoryId) != null) {
      host.openAt(inventoryId, Arrival(inventoryId, changes: true));
    } else {
      navigator.push(MaterialPageRoute<void>(builder: (_) => const InventoriesPage()));
    }
  }

  Future<void> _startNotifications() async {
    await DateNotifier.instance.attach(widget.store, onOpen: _openDates, onChanges: _openChanges);
    final payload = await DateNotifier.instance.takeLaunchPayload();
    if (payload == null || payload == 'backup') return;
    if (payload.startsWith(DateNotifier.changesPayload)) {
      _openChanges(DateNotifier.inventoryOf(payload));
    } else {
      _openDates();
    }
  }

  /// Ana ekran kısayolu. Soğuk açılışta envanter yüklenip kaldığı seviye
  /// kurulduktan sonra alınır; uygulama açıkken hemen. Android sabit
  /// kısayolları görevi temizleyip etkinliği yeniden başlatır: pratikte her
  /// kısayol soğuk açılıştır.
  ///
  /// [level] açılışta geri kurulan seviye. Ayardaki son seviyeye burada
  /// güvenilmez: ana ekranın kabuğu ilk çizimde onu "ana ekran" diye ezer,
  /// geri kurulan klasörün ekranı ise henüz çizilmemiştir.
  Future<void> _takeShortcut({String? level}) async {
    if (!_restored) return; // açılış bitince yeniden sorulur
    final shortcut = await PlatformBridge.takeShortcut();
    // Gezginin kendi bağlamı: mağaza ve bildirim alanı onun üstünde.
    final at = _navigatorKey.currentContext;
    if (shortcut == null || at == null || !at.mounted) return;
    switch (shortcut) {
      case 'search':
        await Navigator.of(at).push(MaterialPageRoute<void>(builder: (_) => const SearchPage()));
      case 'scan':
        await scanQrAndOpen(at);
      // Ana ekrandaki alışveriş listesi widget'ına dokunuldu.
      case 'shopping':
        await Navigator.of(at).push(MaterialPageRoute<void>(builder: (_) => const ShoppingPage()));
      case 'new_item':
        // Açık olan seviyeye, alttaki "+" nasıl ekliyorsa öyle.
        final store = widget.store;
        final open = store.byId(level ?? store.settings.lastLevel);
        final parent = open != null && open.isContainer && store.isLive(open) ? open.id : Roots.home;
        final size = MediaQuery.sizeOf(at);
        await NodeActions.create(
          at,
          parentId: parent,
          kind: NodeKind.item,
          from: Rect.fromLTWH(size.width - 74, size.height - 90, 58, 58),
        );
    }
  }

  void _takeArrival() {
    final at = _navigatorKey.currentContext;
    final arrival = at == null ? null : LibraryScope.read(at)?.takeArrival();
    if (arrival == null || at == null) return;
    final navigator = Navigator.of(at);
    if (arrival.shopping) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => const ShoppingPage()));
      return;
    }
    if (arrival.changes) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => const ChangesPage()));
      return;
    }
    if (arrival.dates) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => const DatesPage()));
      return;
    }
    final store = widget.store;
    final node = store.byId(arrival.recordId);
    if (node == null || !store.isLive(node)) {
      _messengerKey.currentState?.showSnackBar(SnackBar(content: Text(store.strings.qrRecordMissing)));
      return;
    }
    if (node.isContainer && arrival.inside) {
      navigator.popUntil((r) => r.isFirst);
      for (final n in [...store.ancestorsOf(node.id), node]) {
        navigator.push(_instant(ContainerScreen(containerId: n.id)));
      }
    } else if (arrival.inside) {
      showNodeFocus(at, node);
    } else {
      revealNode(at, node);
    }
  }

  void _captureLastLevel() {
    if (_captured) return;
    _captured = true;
    _pendingLevel = widget.store.settings.lastLevel;
  }

  /// Uygulama kapanmadan önce açık olan klasöre geri döner: ana ekranın
  /// üstüne o klasöre kadar olan zincir yığılır, böylece geri tuşu da
  /// beklendiği gibi çalışır. Klasör silinmişse ana ekranda kalınır.
  void _restoreLastLevel() {
    if (_restored) return;
    _restored = true;
    final store = widget.store;
    final id = _pendingLevel;
    final target = store.byId(id);
    final navigator = _navigatorKey.currentState;
    // Üstü çöpteyse de açılmaz: çöp işareti yalnızca klasörün kendisinde, içindekilerde değil.
    final restore = id != null && target != null && store.isLive(target) && target.isContainer && navigator != null;
    if (restore) {
      for (final node in [...store.ancestorsOf(id), target]) {
        navigator.push(_instant(ContainerScreen(containerId: node.id)));
      }
    }
    // Başka envanterden gelindiyse (arama, QR, alışveriş listesi) o iş; uygulama
    // bir kısayoldan açıldıysa kaldığı yerin üstünde.
    _takeArrival();
    _takeShortcut(level: restore ? id : Roots.home);
    // Açılışta: haftalık otomatik yedeğin vakti geldiyse; hiç kurulmadıysa ve
    // envanter büyüdüyse bir kez önerilir.
    AutoBackup.runIfDue(store);
    _offerBackup();
    // Son kullanma bildirimleri; uygulama bir bildirimle açıldıysa listesi.
    _startNotifications();
    // Ana ekrandaki alışveriş listesi widget'ı.
    ShoppingWidgetSync.instance.attach(store);
  }

  /// Geri yüklenen ekranlar animasyonsuz açılır (uygulama zaten yeni açıldı);
  /// geri dönerken normal geçiş kalır.
  static Route<void> _instant(Widget page) => PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 260),
      );

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    // Kapsamlar MaterialApp'in üstünde: bütün route'lar erişebiliyor.
    return InventoryScope(
      store: store,
      child: SharingScope(
        service: widget.sharing,
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) => MaterialApp(
            navigatorKey: _navigatorKey,
            scaffoldMessengerKey: _messengerKey,
            navigatorObservers: [inventoryRouteObserver],
            builder: (context, child) {
              // Durum ve gezinme çubukları kağıt zemine uysun.
              final dark = Theme.of(context).brightness == Brightness.dark;
              final paper = Theme.of(context).scaffoldBackgroundColor;
              // Yatayda başlıklar tek satır (bkz. ShellHeader.landscape).
              ShellHeader.landscape = landscapeLayout(context);
              final host = LibraryScope.maybeOf(context);
              // Envanterden çıkarken yedek yazılıyor: dokunuşlar beklesin.
              final progress = host?.backupAllProgress;
              final busy = progress != null || (host?.backingUp ?? false);
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                  statusBarBrightness: dark ? Brightness.dark : Brightness.light,
                  systemNavigationBarColor: paper,
                  systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                ),
                child: Stack(
                  children: [
                    NotificationListener<ScrollNotification>(
                      // Kaydırma başlayınca yazma biter; −/+ kazası koruması da buradan.
                      onNotification: (n) => dismissKeyboardOnDrag(n) || ScrollGuard.observe(n),
                      child: SharingHost(
                        navigatorKey: _navigatorKey,
                        messengerKey: _messengerKey,
                        child: child ?? const SizedBox.shrink(),
                      ),
                    ),
                    if (busy)
                      Positioned.fill(
                        child: ColoredBox(
                          color: paper.withValues(alpha: 0.85),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 18),
                                Material(
                                  type: MaterialType.transparency,
                                  child: Text(
                                    progress == null
                                        ? store.strings.backingUp
                                        : store.strings.backingUpAll(
                                            math.min(progress.$1 + 1, progress.$2), progress.$2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
            onGenerateTitle: (context) => store.strings.appTitle,
            debugShowCheckedModeBanner: false,
            locale: store.strings.locale,
            supportedLocales: const [Locale('tr'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildTheme(Brightness.light),
            darkTheme: buildTheme(Brightness.dark),
            themeMode: store.settings.themeMode,
            home: store.loading
                ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                : Builder(builder: (context) {
                    _captureLastLevel();
                    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreLastLevel());
                    return const HomeScreen();
                  }),
          ),
        ),
      ),
    );
  }
}
