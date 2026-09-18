import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/strings.dart';
import '../core/time_span.dart';
import '../data/library.dart';
import '../state/inventory_store.dart';
import 'date_alerts.dart';

/// Son kullanma, garanti ve periyodik bakım için telefon bildirimleri. Uygulama kapalıyken de
/// gelsin diye alarmlar Android'e önceden verilir; envanter ya da ayar her
/// değiştiğinde (biraz bekleyip) yeniden kurulur. Tam zamanlı alarm izni
/// istenmez: bildirim birkaç dakika geç gelebilir, sabah dokuzda olması yeter.
class DateNotifier {
  DateNotifier._();

  static final instance = DateNotifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  InventoryStore? _store;
  Timer? _debounce;
  String? _lastPlan;
  bool _ready = false;
  void Function()? _onOpen;
  void Function(String? inventoryId)? _onChanges;

  /// Bildirim izni: null bilinmiyor (eklenti yok, ör. testler).
  final ValueNotifier<bool?> permitted = ValueNotifier(null);

  static const _channelId = 'dates';

  /// Onay bekleyenler bildiriminin kimliği (tek bildirim: yenisi eskisinin yerine geçer).
  static const _pendingId = 2;

  /// Onay bekleyenler bildiriminin yükü: tek envanterse kimliğiyle.
  static const changesPayload = 'changes';

  /// [changesPayload] ile başlayan yükteki envanter kimliği (birkaç envanterse null).
  static String? inventoryOf(String payload) =>
      payload.length > changesPayload.length + 1 ? payload.substring(changesPayload.length + 1) : null;

  /// Açılışta bir kez: eklentiyi kurar, mağazayı dinler, planı kurar.
  /// [onOpen] tarih bildirimine, [onChanges] onay bekleyenler bildirimine dokunulunca
  /// (uygulama açıkken) çağrılır.
  Future<void> attach(
    InventoryStore store, {
    required void Function() onOpen,
    void Function(String? inventoryId)? onChanges,
  }) async {
    _onOpen = onOpen;
    _onChanges = onChanges;
    if (identical(store, _store)) return;
    _store?.removeListener(_changed);
    _store = store;
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_envanter')),
        onDidReceiveNotificationResponse: (r) => tapped(r.payload ?? ''),
      );
      _ready = true;
    } on Object {
      return; // eklenti yok (testler): bildirim de yok
    }
    store.addListener(_changed);
    await refreshPermission();
    await reschedule();
  }

  /// Uygulama açıkken bir bildirime dokunuldu. Yedek bildirimi yalnızca uygulamayı açar;
  /// tarih bildirimi listeyi, onay bekleyenler bildirimi o envanterin değişikliklerini.
  @visibleForTesting
  void tapped(String payload) {
    if (payload.startsWith(changesPayload)) {
      _onChanges?.call(inventoryOf(payload));
    } else if (payload != 'backup') {
      _onOpen?.call();
    }
  }

  bool _launchTaken = false;

  /// Uygulama bir bildirime dokunularak açıldıysa (soğuk açılış) o bildirimin yükü.
  /// Süreç boyunca **bir kez** verilir: eklenti aynı yanıtı her soruşta döner, arayüz ise
  /// envanter değişince baştan kurulur (aynı sayfa her geçişte yeniden açılırdı).
  Future<String?> takeLaunchPayload() async {
    if (!_ready || _launchTaken) return null;
    _launchTaken = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (!(details?.didNotificationLaunchApp ?? false)) return null;
      return details?.notificationResponse?.payload ?? 'dates';
    } on Object {
      return null;
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> refreshPermission() async {
    if (!_ready) return;
    try {
      permitted.value = await _android?.areNotificationsEnabled() ?? true;
    } on Object {
      permitted.value = null;
    }
  }

  /// Android 13+ izin penceresi. Sonuç [permitted]'a yazılır.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final granted = await _android?.requestNotificationsPermission() ?? true;
      permitted.value = granted;
      return granted;
    } on Object {
      return false;
    }
  }

  /// İlk kez tarihli bir eşya kaydedilince izni bir kez sorar: soru bağlamında
  /// gelsin, uygulama açılır açılmaz değil.
  ///
  /// [sharing]: ortak kullanım açılırken de aynı soru (onay bekleyenler bildirimi için);
  /// hangisi önce olursa, bir kez.
  Future<void> askOnce({bool sharing = false}) async {
    final store = _store;
    if (store == null || !_ready || store.settings.notifyAsked) return;
    if (!(sharing ? store.settings.notifyPending : store.settings.dateNotifications)) return;
    await store.updateSettings(store.settings.copyWith(notifyAsked: true));
    if (permitted.value != true) await requestPermission();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(reschedule()));
  }

  /// Planı yeniden kurar; değişmediyse dokunmaz. Gösterilmiş bildirimler
  /// kalır, yalnızca bekleyen alarmlar yenilenir.
  Future<void> reschedule() async {
    final store = _store;
    if (!_ready || store == null || store.loading) return;
    final s = store.strings;
    final now = DateTime.now();
    // Açık envanterinkiler canlı; kapalı envanterlerinki kapanırken saklandı
    // (kapalı envanter değişmez). Bildirim her envanterin kendi ayarı: kapalı
    // olanın satırları zaten saklanmadı. Aynı güne düşenler tek bildirimde.
    final rows = <DateTime, List<SavedAlert>>{};
    final library = InventoryLibrary.current;
    if (store.settings.dateNotifications) {
      for (final a in snapshot(store, label: library?.labelFor(s.appTitle), now: now)) {
        (rows[a.day] ??= []).add(a);
      }
    }
    for (final e in library?.entries ?? const <InventoryEntry>[]) {
      if (e.id == library!.activeId) continue;
      for (final a in e.alerts) {
        final day = dateOnly(a.day);
        if (!DateTime(day.year, day.month, day.day, notifyHour).isAfter(now)) continue;
        (rows[day] ??= []).add(a);
      }
    }
    final days = rows.keys.toList()..sort();
    final plan = [
      for (final d in days.take(30))
        (id: _idOf(d), at: DateTime(d.year, d.month, d.day, notifyHour), text: _textOf(s, rows[d]!)),
    ];
    final signature = [for (final p in plan) '${p.id}:${p.text.title}:${p.text.body}'].join('|');
    if (signature == _lastPlan) return;
    _lastPlan = signature;
    try {
      for (final pending in await _plugin.pendingNotificationRequests()) {
        await _plugin.cancel(id: pending.id);
      }
      for (final p in plan) {
        await _plugin.zonedSchedule(
          id: p.id,
          title: p.text.title,
          body: p.text.body,
          // Gün ve saat yerel; Android'e mutlak an olarak verilir.
          scheduledDate: tz.TZDateTime.from(p.at, tz.UTC),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              s.notifyChannel,
              channelDescription: s.notifyChannelHint,
              styleInformation: BigTextStyleInformation(p.text.body),
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: 'dates',
        );
      }
    } on Object {
      _lastPlan = null; // bir dahakine yeniden denensin
    }
  }

  /// Otomatik yedek yazılamadı: yalnızca Ayarlar'da görünüyordu, klasör silinse
  /// haftalarca fark edilmezdi. Hemen gösterilir (plan değil; [reschedule]
  /// bekleyenleri siler ama gösterilmiş bildirime dokunmaz).
  Future<void> backupFailed(AppStrings s) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: 1,
        title: s.autoBackupTitle,
        body: s.autoBackupFailed,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'backup',
            s.autoBackupTitle,
            channelDescription: s.autoBackupFailed,
          ),
        ),
        payload: 'backup',
      );
    } on Object {
      // Bildirim gösterilemedi: Ayarlar'daki uyarı yine durur.
    }
  }

  /// Onay bekleyen yeni değişiklikler (bkz. `PendingNotice`): hemen gösterilir, öncekinin
  /// yerine geçer. İzin yoksa Android göstermez; sessizce geçilir.
  Future<void> pendingChanges(AppStrings s, {required String title, required String body, String? inventoryId}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _pendingId,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'changes',
            s.pendingChannel,
            channelDescription: s.pendingChannelHint,
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
        payload: inventoryId == null ? changesPayload : '$changesPayload:$inventoryId',
      );
    } on Object {
      // Gösterilemedi: envanter listesindeki işaret yine durur.
    }
  }

  /// Uygulama öne geldi: bekleyenler artık arayüzde görünüyor.
  Future<void> clearPending() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: _pendingId);
    } on Object {
      // Eklenti yanıt vermedi: bildirim dokununca kapanır.
    }
  }

  /// Gün başına tek bildirim: kimlik yyyymmdd.
  static int _idOf(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

  /// Bir envanterin bildirim satırları (gün, ad, metin). Kapanan envanterin
  /// satırları kütüphanede saklanır; birden çok envanter varken ada envanterin
  /// adı eklenir ("Süt · Ev"), hangi evdeki süt olduğu bilinsin. Kapalı
  /// envanter için bir yıl ileriye bakılır: o kadar açılmasa da haber verilir.
  static List<SavedAlert> snapshot(InventoryStore store, {String? label, required DateTime now, int maxDays = 30}) {
    final s = store.strings;
    return [
      for (final a in store.dateAlerts(now, maxDays: maxDays))
        for (final (n, kind, date) in a.items)
          SavedAlert(
            day: dateOnly(a.day),
            name: label == null ? store.nameOf(n) : '${store.nameOf(n)} · $label',
            line: switch (kind) {
              DateAlertKind.expiring => s.notifyExpiring(s.formatDate(date), daysBetween(a.day, date)),
              DateAlertKind.lastDay => s.notifyLastDay,
              DateAlertKind.warranty => s.notifyWarranty(s.formatDate(date)),
              DateAlertKind.service => s.notifyService(n.serviceTask),
            },
          ),
    ];
  }

  static ({String title, String body}) _textOf(AppStrings s, List<SavedAlert> rows) {
    if (rows.length == 1) return (title: rows.single.name, body: rows.single.line);
    return (
      title: s.notifyManyTitle(rows.length),
      body: [for (final r in rows) '${r.name}: ${r.line}'].join('\n'),
    );
  }
}
