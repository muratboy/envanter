import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/inventory_host.dart';
import '../../state/inventory_store.dart';
import '../../sync/review.dart';
import '../../sync/sharing_service.dart';
import '../../sync/wire.dart';
import '../backup_flows.dart';
import '../shell.dart';
import 'changes_page.dart';
import 'sharing_flows.dart';
import 'sharing_scope.dart';

/// Uygulamanın en üstünde durur:
///  - uygulama arka plana geçince ağı durdurur, öne gelince yeniden açar
///    (Android arka planda soketleri zaten kapatıyor);
///  - ana kullanıcıya, hangi ekranda olursa olsun, katılma isteğini sorar;
///  - karşıdan yeni değişiklik gelince kısa bir bildirim gösterir.
class SharingHost extends StatefulWidget {
  const SharingHost({
    super.key,
    required this.navigatorKey,
    required this.messengerKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final GlobalKey<ScaffoldMessengerState> messengerKey;
  final Widget child;

  @override
  State<SharingHost> createState() => _SharingHostState();
}

class _SharingHostState extends State<SharingHost> with WidgetsBindingObserver {
  final Set<PendingJoin> _asked = {};
  SharingService? _service;
  InventoryStore? _store;
  InventoryHost? _host;

  /// Yeni envanter olarak katılırken gösterilen bekleme penceresi açık mı.
  bool _joinDialog = false;

  /// Bildirimi gösterilmiş değişiklikler; ilk yüklemedekiler sessizce sayılır.
  Set<String>? _seenChanges;
  StreamSubscription<LostEvent>? _lostSub;
  StreamSubscription<AuthorityEvent>? _authoritySub;
  StreamSubscription<IncompatibleEvent>? _incompatibleSub;
  StreamSubscription<String>? _removedSub;
  StreamSubscription<GovernanceEvent>? _governanceSub;
  StreamSubscription<List<Notice>>? _noticeSub;
  StreamSubscription<ClockEvent>? _clockSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = SharingScope.read(context);
    if (!identical(service, _service)) {
      _service?.removeListener(_onChange);
      _service = service..addListener(_onChange);
      _incompatibleSub?.cancel();
      _incompatibleSub = service.incompatibleEvents.listen(_onIncompatible);
      _removedSub?.cancel();
      _removedSub = service.removedEvents.listen(_onRemoved);
      _governanceSub?.cancel();
      _governanceSub = service.governanceEvents.listen(_onGovernance);
      _noticeSub?.cancel();
      _noticeSub = service.noticeEvents.listen(_onNotices);
      _clockSub?.cancel();
      _clockSub = service.clockEvents.listen(_onClock);
    }
    final host = LibraryScope.read(context);
    if (!identical(host, _host)) {
      _host?.removeListener(_onHostChange);
      _host = host?..addListener(_onHostChange);
      // Envanter değişince bu arayüz yeni kuruldu: süren katılma ya da sonucu.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onHostChange());
    }
    final store = InventoryScope.read(context);
    if (!identical(store, _store)) {
      _store?.removeListener(_onStoreChange);
      _lostSub?.cancel();
      _store = store..addListener(_onStoreChange);
      _lostSub = store.lostEvents.listen(_onLost);
      _authoritySub?.cancel();
      _authoritySub = store.authorityEvents.listen(_onAuthority);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service?.removeListener(_onChange);
    _store?.removeListener(_onStoreChange);
    _lostSub?.cancel();
    _authoritySub?.cancel();
    _incompatibleSub?.cancel();
    _removedSub?.cancel();
    _governanceSub?.cancel();
    _noticeSub?.cancel();
    _clockSub?.cancel();
    _host?.removeListener(_onHostChange);
    super.dispose();
  }

  /// Yeni envanter olarak katılma: onay beklenirken kapatılamayan pencere,
  /// bitince sonucu. Katılma envanter geçişiyle başladığı için eski arayüz
  /// gösteremez; bu (yeni) arayüz gösterir.
  void _onHostChange() {
    final host = _host;
    final store = _store;
    if (host == null || store == null || !mounted) return;
    // Geçişte kapanmakta olan eski arayüz de haber alır; göstermesin.
    if (!identical(store, host.session.store)) return;
    final s = store.strings;
    final owner = host.joiningOwner;
    final navigator = widget.navigatorKey.currentState;
    if (owner != null && !_joinDialog && navigator != null) {
      _joinDialog = true;
      showDialog<void>(
        context: navigator.context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
                const SizedBox(width: 18),
                Expanded(child: Text(s.waitingForApproval(owner))),
              ],
            ),
          ),
        ),
      );
      return;
    }
    if (owner == null && _joinDialog) {
      _joinDialog = false;
      navigator?.pop();
    }
    if (host.takeRecovery() case final name?) _showRecovery(name);
    if (host.takePendingDelete() case final id?) _finishDelete(host, id);
    final result = owner == null ? host.takeJoinResult() : null;
    if (result == null) return;
    final messenger = widget.messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Text(switch (result.outcome) {
        JoinOutcome.accepted => s.joinedMessage(result.inventory),
        JoinOutcome.rejected => s.joinRejected,
        JoinOutcome.unreachable => s.joinUnreachable,
        JoinOutcome.timeout => s.joinTimeout,
        JoinOutcome.incompatible => s.joinIncompatible,
      }),
    ));
  }

  /// Bu cihazda yapılan bir değişikliği başkası geri çevirdi: aynısını yeniden
  /// yapmasın diye söylenir. Tek haber ayrıntılı, çoksa kişi başına sayı.
  void _onNotices(List<Notice> notices) {
    final s = _store?.strings;
    final service = _service;
    if (s == null || service == null || notices.isEmpty) return;
    String who(String id) => service.memberName(id) ?? s.user;
    final byWho = <String, List<Notice>>{};
    for (final n in notices) {
      (byWho[n.by] ??= []).add(n);
    }
    final text = [
      for (final e in byWho.entries)
        e.value.length == 1
            ? s.rejectedNotice(who(e.key), e.value.single.name, e.value.single.kind)
            : s.rejectedNoticeMany(who(e.key), e.value.length),
    ].join('\n');
    final messenger = widget.messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 6)));
  }

  /// Bir üyeyle saatler çok farklı: hangisinin yanlış olduğu ve düzeltilip
  /// düzeltilmediği söylenir (oturumda üye başına bir kez).
  void _onClock(ClockEvent event) {
    final s = _store?.strings;
    if (s == null) return;
    final who = event.name ?? s.user;
    final span = s.clockSpan(event.skewMs.abs() ~/ 60000);
    final ahead = event.skewMs > 0; // onunki bizimkinden ileri
    final text = event.mineWrong
        ? s.clockMineWrong(who, span, ahead)
        : event.theirsWrong
            ? s.clockTheirsWrong(who, span, ahead)
            : s.clockUnknown(who, span);
    final messenger = widget.messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 8)));
  }

  /// Veritabanı açılamadı, envanter boş açıldı: yedekten geri yükleme önerilir.
  Future<void> _showRecovery(String name) async {
    final context = widget.navigatorKey.currentContext;
    final s = _store?.strings;
    if (context == null || s == null) return;
    final import = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.healing_rounded),
        title: Text(s.recoveryTitle),
        content: Text(s.recoveryBody(name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.close)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.importTitle)),
        ],
      ),
    );
    final now = widget.navigatorKey.currentContext;
    if (import == true && now != null && now.mounted) await BackupFlows.import(now);
  }

  /// Paylaşılan kapalı envanter silinmek üzere açıldı: diğerlerine haber
  /// verilir (yöneticiyse yönetimi kime bırakacağı sorulur), sonra silinir.
  Future<void> _finishDelete(InventoryHost host, String id) async {
    await host.session.ready;
    final context = widget.navigatorKey.currentContext;
    if (context == null || !context.mounted || host.session.id != id) return;
    if (host.session.sharing.config.isShared && !await SharingFlows.leave(context, deleting: true)) return;
    await host.delete(id);
  }

  /// Yönetici değişti, varis seçildi, biri ayrıldı ya da envanteri sildi.
  /// Yönetim bu cihaza geçtiyse açıkça söylenir (pencere); ötekiler kısa bildirim.
  Future<void> _onGovernance(GovernanceEvent event) async {
    final store = _store;
    final service = _service;
    if (store == null || service == null) return;
    final s = store.strings;
    final messenger = widget.messengerKey.currentState;
    void note(String text) {
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 5)));
    }

    if (event.newOwner != null) {
      if (event.newOwner == service.config.deviceId) {
        final context = widget.navigatorKey.currentContext;
        if (context == null || !context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.workspace_premium_rounded),
            title: Text(s.youAreOwnerTitle),
            content: Text(s.youAreOwnerBody(event.previousOwner ?? s.someone)),
            actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.gotIt))],
          ),
        );
      } else {
        note(s.newOwnerIs(service.memberName(event.newOwner) ?? s.someone));
      }
      return;
    }
    if (event.heirToMe) {
      note(s.heirToYou(service.memberName(service.config.ownerDeviceId) ?? s.someone));
      return;
    }
    if (event.leftName case final name?) {
      note(event.deleted ? s.memberDeletedInventory(name) : s.memberLeft(name));
    }
  }

  /// Bir ana kullanıcı bizi çıkardı: cihaz kendi envanterine döndü. Onay
  /// bekleyen değişiklikler artık geçersiz; kullanıcıya açıkça söylenir.
  Future<void> _onRemoved(String inventory) async {
    final store = _store;
    final context = widget.navigatorKey.currentContext;
    if (store == null) return;
    await store.discardPendingChanges();
    if (context == null || !context.mounted) return;
    final s = store.strings;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.person_remove_rounded),
        title: Text(s.removedFromSharingTitle),
        content: Text(s.removedFromSharingBody(inventory)),
        actions: [
          FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.gotIt)),
        ],
      ),
    );
  }

  /// Bir üyenin uygulaması farklı sürümde: eşitleme durdu, kim güncellemeli.
  void _onIncompatible(IncompatibleEvent event) {
    final store = _store;
    if (store == null) return;
    final s = store.strings;
    final who = _service?.memberName(event.deviceId) ?? s.someone;
    final messenger = widget.messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: Color(0xFFE08A00)),
          const SizedBox(width: 12),
          Expanded(child: Text(event.theyAreOlder ? s.peerOutdated(who) : s.selfOutdated(who))),
        ],
      ),
      duration: const Duration(seconds: 6),
    ));
  }

  /// Yetkili birinin değişiklikleri onaysız uygulandı; haber verilir.
  void _onAuthority(AuthorityEvent event) {
    final store = _store;
    if (store == null) return;
    final s = store.strings;
    final who = _service?.memberName(event.author) ?? s.someone;
    final messenger = widget.messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.verified_user_rounded, color: Color(0xFF2FB36B)),
          const SizedBox(width: 12),
          Expanded(child: Text(s.appliedByAuthority(who, event.count))),
        ],
      ),
      duration: const Duration(seconds: 4),
    ));
  }

  /// Başka biri bir eşyanın kaybolduğunu ya da bulunduğunu bildirdi. Onay
  /// beklemeden gelir; herkes haberdar olsun diye her zaman gösterilir.
  void _onLost(LostEvent event) {
    final store = _store;
    if (store == null) return;
    final s = store.strings;
    final who = _service?.memberName(event.by) ?? s.someone;
    final name = store.nameOf(event.node);
    final messenger = widget.messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(
            event.found ? Icons.where_to_vote_rounded : Icons.travel_explore_rounded,
            color: event.found ? const Color(0xFF2FB36B) : const Color(0xFFE08A00),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(event.found
                ? s.foundReported(who, name, store.pathLabel(event.node.id))
                : s.lostReported(who, name)),
          ),
        ],
      ),
      duration: const Duration(seconds: 6),
      persist: false,
      action: event.found
          ? null
          : SnackBarAction(
              label: s.show,
              onPressed: () {
                widget.navigatorKey.currentState?.popUntil((r) => r.isFirst);
                WidgetsBinding.instance.addPostFrameCallback((_) => InventoryShell.requestLostPanel());
              },
            ),
    ));
  }

  static String _key(PendingChange c) => '${c.nodeId}@${c.changedAt.millisecondsSinceEpoch}';

  void _onStoreChange() {
    final store = _store;
    if (store == null || store.loading) return;
    final changes = store.pendingChanges;
    final keys = {for (final c in changes) _key(c)};
    final seen = _seenChanges;
    _seenChanges = keys;
    if (seen == null) return;
    final fresh = [for (final c in changes) if (!seen.contains(_key(c))) c];
    if (fresh.isEmpty) return;

    // En çok değişiklik yapan kişinin adıyla.
    final byAuthor = <String?, int>{};
    for (final c in fresh) {
      byAuthor[c.author] = (byAuthor[c.author] ?? 0) + 1;
    }
    final top = byAuthor.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final s = store.strings;
    final who = _service?.memberName(top) ?? s.someone;
    final messenger = widget.messengerKey.currentState;
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(
      content: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, color: Color(0xFFFFB020)),
          const SizedBox(width: 12),
          Expanded(child: Text(s.newChangesFrom(who, fresh.length))),
        ],
      ),
      duration: const Duration(seconds: 5),
      persist: false,
      action: SnackBarAction(
        label: s.show,
        onPressed: () => widget.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ChangesPage()),
        ),
      ),
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final service = _service;
    if (service == null) return;
    if (state == AppLifecycleState.paused) service.pause();
    if (state == AppLifecycleState.resumed) service.resume();
  }

  void _onChange() {
    final service = _service;
    if (service == null) return;
    _asked.removeWhere((p) => !service.pendingJoins.contains(p));
    for (final pending in service.pendingJoins) {
      if (_asked.add(pending)) _ask(service, pending);
    }
  }

  Future<void> _ask(SharingService service, PendingJoin pending) async {
    final navContext = widget.navigatorKey.currentContext;
    if (navContext == null) return;
    final s = InventoryScope.read(context).strings;
    final name = pending.request.name.isEmpty ? s.user : pending.request.name;
    final accepted = await showDialog<bool>(
      context: navContext,
      barrierDismissible: false,
      builder: (dialogContext) {
        // İstek zaman aşımına uğrarsa pencere kendiliğinden kapansın.
        return ListenableBuilder(
          listenable: service,
          builder: (dialogContext, _) {
            if (!service.pendingJoins.contains(pending)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.of(dialogContext).canPop()) Navigator.of(dialogContext).pop();
              });
            }
            return AlertDialog(
              icon: const Icon(Icons.person_add_alt_1_rounded),
              title: Text(s.joinRequestTitle),
              content: Text(s.joinRequestBody(name, service.inventoryName)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(s.reject),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(s.accept),
                ),
              ],
            );
          },
        );
      },
    );
    service.decideJoin(pending, accepted ?? false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
