import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/node.dart';
import 'clock.dart';
import 'discovery.dart';
import 'lan_peer.dart';
import 'merge.dart';
import 'sharing_config.dart';
import 'sync_target.dart';
import 'wire.dart';

/// [incompatible]: katılındı ama iki uygulamanın veri sürümü farklı; biri
/// güncellenene kadar envanter gelmez.
enum JoinOutcome { accepted, rejected, unreachable, timeout, incompatible }

/// Bir üyenin saati bizimkinden çok farklı ([skewMs] = onunki − bizimki).
/// [mineWrong]: bizim saatimiz otomatik değil, onunki otomatik (bizde düzeltilir);
/// [theirsWrong]: tersi (onda düzeltilir). İkisi de değilse hangisi yanlış bilinmez.
class ClockEvent {
  const ClockEvent({this.name, required this.skewMs, required this.mineWrong, required this.theirsWrong});

  final String? name;
  final int skewMs;
  final bool mineWrong;
  final bool theirsWrong;
}

/// Bir üyeyle son eşitleme neden olmadı (üye satırında görünür; yoksa "çevrimiçi" görünüp hiç
/// eşitlenmiyordu). [rejected]: imza tutmadı; saat farkını yeni sürüm kendisi giderir, kalıcıysa
/// karşıdaki uygulama eski ve saatler farklı olabilir. [server]: karşı cihaz durumunu veremedi.
enum SyncFailure { unreachable, timeout, rejected, server, other }

/// Yönetimde bir değişiklik ya da bir üyenin vedası (arayüz haber verir).
class GovernanceEvent {
  const GovernanceEvent({
    this.newOwner,
    this.previousOwner,
    this.heirToMe = false,
    this.leftName,
    this.deleted = false,
  });

  /// Yönetici değişti: yeni yöneticinin kimliği (bu cihaz olabilir).
  final String? newOwner;

  /// Eski yöneticinin adı (ayrıldıysa artık listede yok; ad önceden alınır).
  final String? previousOwner;

  /// Yönetici bu cihazı varis seçti.
  final bool heirToMe;

  /// Ayrılan (ya da envanteri kendi cihazından silen) üyenin adı.
  final String? leftName;
  final bool deleted;
}

/// Veri sürümü farklı bir üye görüldü: güncellenene kadar onunla eşitlenmez.
class IncompatibleEvent {
  const IncompatibleEvent({required this.deviceId, required this.dataVersion});

  final String deviceId;

  /// Onun veri sürümü; bizimkinden küçükse onun uygulaması eski.
  final int dataVersion;

  bool get theyAreOlder => dataVersion < kDataVersion;
}

/// Sahibin ekranında onay bekleyen bir katılma isteği.
class PendingJoin {
  PendingJoin(this.request);
  final JoinRequest request;
  final Completer<bool> _decision = Completer();
}

/// Yerel ağda ortak kullanım.
///
/// Açıkken cihaz kendini duyurur, küçük bir HTTP sunucusu çalıştırır ve aynı
/// ortak envanterin ağdaki diğer üyeleriyle eşitlenir:
///   - bir üye ağda göründüğünde,
///   - bu cihazda bir şey değiştikten kısa süre sonra,
///   - ve güvenlik ağı olarak belirli aralıklarla.
/// Eşitlemeyi başlatan taraf her şeyi kendisi yapar (çek, birleştir, eksik
/// resimleri al, kendi durumunu gönder, karşının eksiklerini yükle); böylece
/// karşının geri bağlanması gerekmez.
class SharingService extends ChangeNotifier {
  SharingService({
    required this.target,
    required this.configStore,
    required this.displayName,
    LanDiscovery? discovery,
    this.setMulticastLock,
    this.debounce = const Duration(milliseconds: 1500),
    this.periodic = const Duration(seconds: 30),
    this.joinWait = const Duration(seconds: 80),
    this.resyncAfter = const Duration(seconds: 20),
    this.clock = SyncClock.now,
    this.clockTrusted = _clockTrusted,
  }) : discovery = discovery ?? LanDiscovery();

  static bool _clockTrusted() => SyncClock.trusted;

  final SyncTarget target;
  final SharingConfigStore configStore;

  /// Bu cihazın kullanıcısının adı (ağda ve katılma isteğinde görünür).
  final String Function() displayName;
  final LanDiscovery discovery;
  final Future<void> Function(bool held)? setMulticastLock;
  final Duration debounce;
  final Duration periodic;
  final Duration joinWait;

  /// Aynı üyeyle bu süreden sık, bulma tetiklemesiyle eşitlenilmez.
  final Duration resyncAfter;

  /// Karşıya bildirilen saat ve otomatik olup olmadığı (testlerde iki cihaz
  /// aynı süreçte olduğu için ayrı verilebilir).
  final DateTime Function() clock;
  final bool Function() clockTrusted;

  late SharingConfig _config;
  SharingConfig get config => _config;

  bool _loaded = false;
  bool _running = false;
  bool _paused = false;
  PeerServer? _server;
  StreamSubscription<List<DiscoveredPeer>>? _peersSub;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  final Map<String, DateTime> _lastSyncWith = {};

  /// Üyelerin saatiyle bu cihazınki arasındaki fark (imzalar için, bkz. [PeerClient.timeShift]).
  final Map<String, Duration> _timeShifts = {};

  /// Son eşitlemesi olmayan üyeler ve nedeni; eşitlenince düşer.
  final Map<String, SyncFailure> _failures = {};

  SyncFailure? failureWith(String deviceId) => _failures[deviceId];

  /// Ek dosyalarını çeken işler (üye → iş), o an indirilen yollar ve açık
  /// bağlantılar. Kayıt eşitlemesinden ayrı yürür: büyük bir video inerken
  /// kayıtlar o üyeyle eşitlenmeye devam etsin.
  final Map<String, Future<void>> _filePulls = {};
  final Set<String> _fetching = {};
  final Set<PeerClient> _fileClients = {};

  /// Süren alışverişlerin bağlantıları (kapanırken ağ beklemesi kesilsin) ve mağazaya ya da
  /// ayarlara yazabilecek süren işler: bir üyeyle alışveriş, gelen durumun ya da resmin
  /// işlenmesi. [shutdown] bunlar bitmeden dönmez.
  final Set<PeerClient> _syncClients = {};
  final Set<Future<void>> _busy = {};

  /// [shutdown] başladı: bu servis artık hiçbir şey yazmaz, ağı da yeniden açmaz.
  bool _closed = false;

  /// İnmekte olan eklerin ilerlemesi (yol → yüzde, 0–100). Ayrı bir dinlenen:
  /// servisin kendi haberiyle verilseydi her yüzdede bütün ekran yeniden
  /// kurulurdu; bunu yalnızca eki gösteren satır dinler.
  final ValueNotifier<Map<String, int>> fileProgress = ValueNotifier(const {});

  void _setProgress(String rel, int? percent) {
    final now = fileProgress.value;
    if (now[rel] == percent) return;
    fileProgress.value = {
      for (final e in now.entries)
        if (e.key != rel) e.key: e.value,
      rel: ?percent,
    };
  }

  /// Veri sürümü farklı üyeler (kimlik → onun sürümü). Başarılı eşitlemede düşer.
  final Map<String, int> _incompatible = {};

  final StreamController<IncompatibleEvent> _incompatibleEvents = StreamController.broadcast();

  /// Bir üyenin sürümü farklı çıktı (her üye için bir kez; bildirim için).
  Stream<IncompatibleEvent> get incompatibleEvents => _incompatibleEvents.stream;

  final StreamController<GovernanceEvent> _governanceEvents = StreamController.broadcast();

  /// Yönetici değişti, varis seçildi ya da biri ayrıldı / envanteri sildi.
  Stream<GovernanceEvent> get governanceEvents => _governanceEvents.stream;

  final StreamController<String> _removedEvents = StreamController.broadcast();

  /// Bir ana kullanıcı bizi ortak kullanımdan çıkardı (envanterin adı). Cihaz
  /// kendi envanterine döndü; kayıtlar yerinde, artık eşitlenmiyor.
  Stream<String> get removedEvents => _removedEvents.stream;

  /// Üyenin veri sürümü bizimkinden farklıysa onunki; değilse null.
  int? incompatibleVersion(String deviceId) => _incompatible[deviceId];

  /// Karşının sürümü görüldü: tutuyorsa işaret kalkar, tutmuyorsa konur.
  void _notePeerVersion(String? deviceId, int dataVersion) {
    if (dataVersion != kDataVersion) return _markIncompatible(deviceId, dataVersion);
    if (deviceId != null && _incompatible.remove(deviceId) != null) notifyListeners();
  }

  void _markIncompatible(String? deviceId, int dataVersion) {
    if (deviceId == null || deviceId == _config.deviceId || !_config.isMember(deviceId)) return;
    if (_incompatible[deviceId] == dataVersion) return;
    _incompatible[deviceId] = dataVersion;
    _incompatibleEvents.add(IncompatibleEvent(deviceId: deviceId, dataVersion: dataVersion));
    notifyListeners();
  }

  /// Üye başına son *tam* eşitlemede iki tarafın durum damgası. İkisi de
  /// aynı kaldıysa konuşacak bir şey yok demektir.
  final Map<String, ({String ours, String theirs})> _syncedStamps = {};
  final Set<String> _syncing = {};
  final List<PendingJoin> _pending = [];

  /// Son eşitleme denemesinin hatası; başarılı eşitlemede temizlenir.
  String? lastError;

  /// Kullanıcının istediği ağ taraması sürüyor.
  bool scanning = false;

  /// Bu açılışta ağ en son ne zaman tarandı; taranmadıysa null. Ağdaki
  /// envanterler yalnızca taramadan sonra gösterilir.
  DateTime? lastScanAt;

  /// Ağı kısa bir süre tarar: soruyu birkaç kez yayınlar, yanıtları toplar.
  Future<void> scan({Duration window = const Duration(seconds: 6)}) async {
    if (!_running || scanning) return;
    scanning = true;
    notifyListeners();
    try {
      final end = DateTime.now().add(window);
      while (_running && DateTime.now().isBefore(end)) {
        await discovery.probe();
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    } finally {
      scanning = false;
      lastScanAt = DateTime.now();
      notifyListeners();
    }
  }

  bool get enabled => _loaded && _config.enabled;
  bool get running => _running;
  bool get syncing => _syncing.isNotEmpty;

  /// Ağda görünen, katılınabilecek (bizimki olmayan) envanterler.
  List<DiscoveredPeer> get joinableInventories => [
        for (final p in discovery.peers)
          if (p.info.joinable && p.info.inventoryId != _config.inventoryId) p,
      ];

  /// Aynı ortak envanterin şu an ağda görünen diğer üyeleri. Duyurular
  /// imzasız: envanter kimliğini söyleyen herkese değil, yalnızca kabul
  /// edilmiş üyelere durumumuzu veririz.
  List<DiscoveredPeer> get onlineMembers => [
        for (final p in discovery.peers)
          if (p.info.inventoryId == _config.inventoryId && _config.isMember(p.info.deviceId)) p,
      ];

  List<PendingJoin> get pendingJoins => List.unmodifiable(_pending);

  /// Ağda görünen ad; boşsa kullanıcının adı.
  String get inventoryName =>
      _config.inventoryName.trim().isNotEmpty ? _config.inventoryName.trim() : displayName();

  Future<void> load() async {
    _config = await configStore.load() ?? SharingConfig.fresh();
    await _save(); // ilk açılışta üretilen kimlikler kalsın
    _loaded = true;
    target.localRevision.addListener(_onLocalChange);
    if (_config.enabled) await _start();
    notifyListeners();
  }

  bool _disposed = false;

  /// Sunucuyu, bulmayı ve zamanlayıcıları kapatır; beklenebilir. Süren bir alışveriş ya da
  /// işlenen bir istek varsa ağ beklemesi kesilir ve işin bitmesi beklenir; döndükten sonra
  /// bu servis ne mağazaya ne ayarlara yazar. Yazımlar o an açık olan veritabanına gittiği
  /// için, envanter değişirken yanıtı geç gelen alışveriş eski envanterin kayıtlarını ve
  /// ortak kullanım kimliğini (anahtar, üyeler) yeni açılan envantere yazıyordu.
  Future<void> shutdown() async {
    _closed = true;
    if (_loaded) target.localRevision.removeListener(_onLocalChange);
    await _stop();
    for (final c in List.of(_syncClients)) {
      c.close();
    }
    await discovery.dispose();
    // Takılan bir iş olursa (olmamalı) geçiş sonsuza dek beklemesin: yazımlar zaten
    // [_closed] ile kapalı.
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (_busy.isNotEmpty || _filePulls.isNotEmpty) {
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) break;
      await Future.wait<void>([
        ..._busy,
        for (final pull in _filePulls.values) pull.then<void>((_) {}, onError: (Object _) {}),
      ]).timeout(left, onTimeout: () => const []);
    }
  }

  /// [work] bitene kadar "süren iş" sayılır (bkz. [shutdown]).
  Future<T> _tracked<T>(Future<T> work) {
    late final Future<void> mark;
    mark = work.then<void>((_) {}, onError: (Object _) {}).whenComplete(() => _busy.remove(mark));
    _busy.add(mark);
    return work;
  }

  /// Kapanış başladıysa süren alışveriş burada bırakılır.
  void _checkOpen() {
    if (_closed) throw const PeerException('kapandı');
  }

  /// Ayarların yazıldığı tek yer; kapanış başladıktan sonra yazılmaz (bkz. [shutdown]).
  Future<void> _save() async {
    if (!_closed) await configStore.save(_config);
  }

  /// Kapandıktan sonra süren bir eşitleme ya da istek bildirim göndermesin.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(shutdown());
    super.dispose();
  }

  // ---------------------------------------------------------------- aç/kapat

  Future<void> setEnabled(bool on) async {
    _config = _config.copyWith(enabled: on);
    await _save();
    if (on) {
      _paused = false;
      await _start();
    } else {
      await _stop();
    }
    notifyListeners();
  }

  Future<void> rename(String name) async {
    _config = _config.copyWith(inventoryName: name.trim());
    await _save();
    if (_running) await discovery.announceNow();
    notifyListeners();
  }

  /// Uygulama arka plana geçince; Android arka planda soketleri kapatıyor.
  Future<void> pause() async {
    if (!_running) return;
    _paused = true;
    await _stop();
  }

  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    if (_config.enabled) await _start();
  }

  Future<void> _start() async {
    if (_running || _closed) return;
    final server = PeerServer(
      info: _announcement,
      signer: () => RequestSigner(_config.key),
      onJoin: _handleJoin,
      readState: _state,
      applyState: (incoming) => _tracked(_applyIncoming(incoming)),
      readImage: target.readImage,
      saveImage: _saveImage,
      openFile: target.outgoingFile,
      onPeerVersion: _notePeerVersion,
      isRemoved: (id) => _config.isRemovedDevice(id),
      clock: clock,
    );
    await server.start();
    _server = server;
    await setMulticastLock?.call(true);
    try {
      await discovery.start(_announcement);
    } on Object catch (e) {
      // Bulma portu açılamadı (ör. ağ yok); sunucu yine de dursun.
      lastError = '$e';
    }
    _peersSub = discovery.changes.listen(_onPeersChanged);
    _periodicTimer = Timer.periodic(periodic, (_) => unawaited(_syncAll()));
    _running = true;
    // Açılışta bir kez sor: üyeler seyrek duyuruyu beklemeden bulunsun.
    unawaited(discovery.probe());
    notifyListeners();
  }

  Future<void> _stop() async {
    if (!_running) return;
    _running = false;
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    await _peersSub?.cancel();
    _peersSub = null;
    await discovery.stop();
    await _server?.stop();
    _server = null;
    // Süren ek indirmeleri kesilir; yarım dosya bir dahakine baştan gelir.
    for (final c in List.of(_fileClients)) {
      c.close();
    }
    await setMulticastLock?.call(false);
    for (final p in List.of(_pending)) {
      decideJoin(p, false);
    }
    notifyListeners();
  }

  Announcement _announcement() => Announcement(
        deviceId: _config.deviceId,
        deviceName: displayName(),
        inventoryId: _config.inventoryId,
        inventoryName: inventoryName,
        // Ana kullanıcılar da katılma isteği kabul edebilir.
        joinable: _config.isAdmin,
        httpPort: _server?.port ?? 0,
        stamp: _stamp(),
        dataVersion: kDataVersion,
      );

  /// Duyuruda taşınan özet: kayıtlar + üyeler/roller.
  String _stamp([String? nodes]) =>
      '${nodes ?? target.stateStamp}~${memberStampOf(_members(), _config.removed, _config.governance)}'
      '~${noticeStampOf(_config.notices)}';

  // ---------------------------------------------------------------- eşitleme

  List<Member> _members() => [
        for (final m in _config.members)
          m.deviceId == _config.deviceId ? m.copyWith(name: displayName()) : m,
      ];

  SyncState _state() {
    final snap = target.snapshot();
    return SyncState(
      nodes: snap.nodes,
      tombstones: snap.tombstones,
      members: _members(),
      removed: _config.removed,
      governance: _config.governance,
      notices: _config.notices,
      clock: clock().millisecondsSinceEpoch,
      clockTrusted: clockTrusted(),
      from: _config.deviceId,
    );
  }

  // ---------------------------------------------------------------- saat

  /// Üyelerin saat farkı (ms, onunki − bizimki, düzeltmesiz) ve saati otomatik mi.
  final Map<String, ({int skew, bool trusted})> _clocks = {};
  final Set<String> _clockWarned = {};

  /// Saati 2 dakikadan çok farklı üye: (fark ms, kimin saati yanlış görünüyor).
  /// null: fark yok ya da bilinmiyor.
  ({int skewMs, bool mineWrong})? clockIssue(String deviceId) {
    final c = _clocks[deviceId];
    if (c == null || c.skew.abs() < SyncClock.warnAfter.inMilliseconds) return null;
    return (skewMs: c.skew, mineWrong: c.trusted && !SyncClock.trusted);
  }

  final StreamController<ClockEvent> _clockEvents = StreamController.broadcast();

  /// Oturumda bir üyeyle ilk kez büyük saat farkı görüldü.
  Stream<ClockEvent> get clockEvents => _clockEvents.stream;

  /// Karşının saatini gördük; [localMid] isteğin ortasındaki kendi (düzeltmesiz) anımız.
  void _noteClock(String? id, SyncState state, int localMid) {
    final clock = state.clock;
    if (id == null || clock == null || id == _config.deviceId || !_config.isMember(id)) return;
    // Karşının gönderdiği düzeltilmiş saat; bizimkini düzeltmesiz kıyaslarız.
    final skew = clock - localMid;
    _clocks[id] = (skew: skew, trusted: state.clockTrusted);
    if (state.clockTrusted) SyncClock.adopt(skew);
    if (skew.abs() >= SyncClock.warnAfter.inMilliseconds && _clockWarned.add(id)) {
      _clockEvents.add(ClockEvent(
        name: memberName(id),
        skewMs: skew,
        mineWrong: state.clockTrusted && !SyncClock.trusted,
        theirsWrong: SyncClock.trusted && !state.clockTrusted,
      ));
    }
    notifyListeners();
  }

  /// [direct]: katılırken ilk eşitleme; ortak envanter onaysız gelir.
  Future<MergeStats> _mergeState(SyncState incoming, {String? from, bool direct = false}) async {
    _checkOpen();
    final stats = await target.mergeRemote(
      nodes: incoming.nodes,
      tombstones: incoming.tombstones,
      review: !direct && !_config.autoAccept,
      from: incoming.from ?? from,
    );
    // Adlar birleşmeden önce: ayrılan üye listeden düşünce adı bilinmezdi.
    final sender = incoming.from ?? from;
    final senderName = memberName(sender);
    final ownerName = memberName(_config.ownerDeviceId);
    final inventoryId = _config.inventoryId;
    await _mergeMembers(incoming.members, incoming.removed);
    // Çıkarıldığımızı öğrendiysek artık o envanter değiliz.
    if (_config.inventoryId != inventoryId) return stats;
    if (incoming.governance case final g?) await _mergeGovernance(g, previousOwnerName: ownerName);
    await _mergeNotices(incoming.notices);
    if (incoming.farewell != null && sender != null && sender != _config.deviceId) {
      _governanceEvents.add(GovernanceEvent(leftName: senderName, deleted: incoming.farewell == 'deleted'));
    }
    return stats;
  }

  /// Haberlerin birleşimi; bu cihaza yeni gelenler arayüze bir kez iletilir.
  Future<void> _mergeNotices(List<Notice> incoming) async {
    final merged = mergeNotices(_config.notices, incoming, DateTime.now());
    final fresh = [
      for (final n in merged)
        if (n.to == _config.deviceId && !_config.seenNotices.contains(n.id)) n,
    ];
    final ids = {for (final n in merged) n.id};
    final same = merged.length == _config.notices.length && _config.notices.every((n) => ids.contains(n.id));
    if (same && fresh.isEmpty) return;
    _config = _config.copyWith(
      notices: merged,
      // Düşen haberlerin izi de düşer.
      seenNotices: {
        for (final id in _config.seenNotices)
          if (ids.contains(id)) id,
        for (final n in fresh) n.id,
      },
    );
    await _save();
    if (fresh.isNotEmpty) _noticeEvents.add(fresh);
  }

  /// Bu cihazda geri çevrilen değişikliklerin haberleri; yapanlara yayılır.
  Future<void> addNotices(List<Notice> notices) async {
    if (notices.isEmpty) return;
    _config = _config.copyWith(notices: mergeNotices(_config.notices, notices, DateTime.now()));
    await _save();
    notifyListeners();
    _onLocalChange();
  }

  final StreamController<List<Notice>> _noticeEvents = StreamController.broadcast();

  /// Bu cihazın yaptığı, başkasının geri çevirdiği değişiklikler.
  Stream<List<Notice>> get noticeEvents => _noticeEvents.stream;

  /// Yönetici ve varis: her kararda en yenisi. Bu cihaz yönetici ya da varis
  /// olduysa arayüz haber verir.
  Future<void> _mergeGovernance(Governance incoming, {String? previousOwnerName}) async {
    final current = _config.governance;
    final next = current.merge(incoming);
    if (next == current) return;
    _config = _config.withGovernance(next);
    await _save();
    if (_running) await discovery.announceNow();
    notifyListeners();
    if (next.owner != current.owner) {
      _governanceEvents.add(GovernanceEvent(newOwner: next.owner, previousOwner: previousOwnerName));
    } else if (next.heir == _config.deviceId && current.heir != _config.deviceId) {
      _governanceEvents.add(const GovernanceEvent(heirToMe: true));
    }
  }

  /// Varis seçer ya da kaldırır ([deviceId] null). Yalnızca yönetici: varis
  /// kendisi varis seçemez, önce yönetici olması gerekir.
  Future<bool> setHeir(String? deviceId) async {
    if (!_config.isOwner || deviceId == _config.deviceId) return false;
    if (deviceId != null && !_config.isMember(deviceId)) return false;
    await _setGovernance(Governance(
      owner: _config.ownerDeviceId,
      ownerAt: _config.ownerAt,
      heir: deviceId,
      heirAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return true;
  }

  /// Yöneticiliği bir üyeye devreder; devreden otomatik olarak onun varisi olur.
  Future<bool> transferOwnership(String deviceId) async {
    if (!_config.isOwner || deviceId == _config.deviceId || !_config.isMember(deviceId)) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _setGovernance(Governance(owner: deviceId, ownerAt: now, heir: _config.deviceId, heirAt: now));
    return true;
  }

  Future<void> _setGovernance(Governance g) async {
    _config = _config.withGovernance(g);
    await _save();
    if (_running) await discovery.announceNow();
    notifyListeners();
    _onLocalChange();
  }

  /// Değişiklikleri sormadan uygula. Açılınca bekleyenleri arayüz uygular.
  Future<void> setAutoAccept(bool on) async {
    _config = _config.copyWith(autoAccept: on);
    await _save();
    notifyListeners();
  }

  /// Bir cihaz kimliğinin görünen adı (değişiklikleri kimin yaptığı).
  String? memberName(String? deviceId) {
    if (deviceId == null) return null;
    if (deviceId == _config.deviceId) return displayName();
    final name = _config.members.where((m) => m.deviceId == deviceId).firstOrNull?.name;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final seen = discovery.peers.where((p) => p.info.deviceId == deviceId).firstOrNull;
    return seen?.info.deviceName;
  }

  Future<void> _mergeMembers(List<Member> incoming, [Map<String, int> incomingRemoved = const {}]) async {
    final removed = Map<String, int>.of(_config.removed);
    var changed = false;
    incomingRemoved.forEach((id, at) {
      if ((removed[id] ?? 0) < at) {
        removed[id] = at;
        changed = true;
      }
    });
    final byId = {for (final m in _config.members) m.deviceId: m};
    for (final m in incoming) {
      final known = byId[m.deviceId];
      if (known == null) {
        if (m.deviceId == _config.deviceId) continue;
        byId[m.deviceId] = m;
        changed = true;
        continue;
      }
      var next = known;
      // Kendi adımızı başkası belirlemez; rolümüzü ise ana kullanıcı değiştirebilir.
      if (m.deviceId != _config.deviceId && m.name.isNotEmpty && m.name != known.name) {
        next = next.copyWith(name: m.name);
      }
      if (m.roleAt > known.roleAt) next = next.copyWith(admin: m.admin, roleAt: m.roleAt);
      if (m.joinedAt > known.joinedAt) next = next.copyWith(joinedAt: m.joinedAt);
      if (!identical(next, known)) {
        byId[m.deviceId] = next;
        changed = true;
      }
    }
    // Çıkarılma (ya da ayrılma) izinden önce katılmış olanlar listeden düşer.
    byId.removeWhere((id, m) {
      final gone = removed.containsKey(id) && removed[id]! >= m.joinedAt;
      if (gone) changed = true;
      return gone;
    });
    if (!changed) return;
    _config = _config.copyWith(members: byId.values.toList(), removed: removed);
    await _save();
    // Listede kendimiz yoksak bir ana kullanıcı bizi çıkarmış.
    if (!byId.containsKey(_config.deviceId)) return _removedByOthers();
    if (_running) await discovery.announceNow();
    notifyListeners();
  }

  /// Bir üyeyi ortak kullanımdan çıkarır. Yalnızca ana kullanıcılar ve yalnızca
  /// ana kullanıcı olmayanları. Çıkarılan cihazın kayıtları onda kalır; bir
  /// sonraki eşitleme denemesinde çıkarıldığını öğrenip kendi envanterine
  /// döner. Yeniden katılmak isterse istek yine onaya düşer.
  Future<bool> removeMember(String deviceId) async {
    if (!_config.isAdmin || deviceId == _config.deviceId) return false;
    if (!_config.isMember(deviceId) || _config.isAdminDevice(deviceId)) return false;
    _config = _config.copyWith(
      members: [for (final m in _config.members) if (m.deviceId != deviceId) m],
      removed: {..._config.removed, deviceId: DateTime.now().millisecondsSinceEpoch},
    );
    _syncedStamps.remove(deviceId);
    await _save();
    if (_running) await discovery.announceNow();
    notifyListeners();
    _onLocalChange();
    // Ağdaysa hemen haber verilir: bizimle artık eşitlemediği için kendiliğinden
    // ancak bir sonraki düzenli denemesinde (403) öğrenirdi.
    final peer = discovery.peers.where((p) => p.info.deviceId == deviceId).firstOrNull;
    if (peer != null) unawaited(_post(peer, _membersOnly()));
    return true;
  }

  /// Yalnızca üye listesi ve izler: kayıt taşımayan küçük bir durum.
  SyncState _membersOnly() => SyncState(
        nodes: const {},
        tombstones: const {},
        members: _members(),
        removed: _config.removed,
        governance: _config.governance,
        from: _config.deviceId,
      );

  /// [peer]'e istek atan istemci: imzalar bu cihazın saatiyle, o üyeyle öğrenilen farkla atılır.
  PeerClient _clientFor(DiscoveredPeer peer) => PeerClient(
        peer.baseUri,
        signer: RequestSigner(_config.key),
        from: _config.deviceId,
        clock: clock,
        timeShift: _timeShifts[peer.info.deviceId] ?? Duration.zero,
      );

  /// Yanıtı beklenmeyen tek yönlü gönderim (ayrılma, çıkarma haberi).
  Future<void> _post(DiscoveredPeer peer, SyncState state) async {
    final client = _clientFor(peer);
    try {
      await client.postState(state).timeout(const Duration(seconds: 8));
    } on Object {
      // Ağda değil ya da yanıt vermedi: başkalarından ya da 403'ten öğrenir.
    } finally {
      client.close();
    }
  }

  /// Çıkarıldığımızı öğrendik (üye listesinden ya da karşının 403 yanıtından).
  Future<void> _removedByOthers() async {
    final name = inventoryName;
    await _resetToOwn();
    _removedEvents.add(name);
  }

  /// Bir üyeyi genel ana kullanıcı yapar ya da bu yetkiyi alır. Yalnızca ana
  /// kullanıcılar yapabilir; sahibin yetkisi alınamaz.
  Future<bool> setAdmin(String deviceId, bool admin) async {
    if (!_config.isAdmin || deviceId == _config.ownerDeviceId) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    _config = _config.copyWith(
      members: [
        for (final m in _config.members)
          m.deviceId == deviceId ? m.copyWith(admin: admin, roleAt: now) : m,
      ],
    );
    await _save();
    if (_running) await discovery.announceNow();
    notifyListeners();
    _onLocalChange();
    return true;
  }

  bool isAdminDevice(String? deviceId) => _config.isAdminDevice(deviceId);

  /// Karşı cihaz durumunu bize itti: birleştir, eksik resimleri söyle.
  Future<Set<String>> _applyIncoming(SyncState incoming) async {
    _checkOpen();
    _noteClock(incoming.from, incoming, DateTime.now().millisecondsSinceEpoch);
    await _mergeState(incoming);
    if (incoming.from case final from? when _config.isMember(from)) {
      // Karşı taraf bize ulaştı: o üyeyle eşitlenmiş sayılırız.
      _failures.remove(from);
      _config = _config.copyWith(
        syncedWith: {..._config.syncedWith, from: DateTime.now().millisecondsSinceEpoch},
      );
      await _save();
      // Getirdiği kayıtların ekleri: resimler gibi itilmez, biz çekeriz.
      final peer = onlineMembers.where((p) => p.info.deviceId == from).firstOrNull;
      if (peer != null) _pullFiles(peer);
    }
    return target.missingImages();
  }

  /// Karşının yüklediği resim.
  Future<bool> _saveImage(String rel, Uint8List bytes) async {
    if (_closed) return false;
    return _tracked(target.saveImage(rel, bytes));
  }

  /// Eksik ek dosyalarını [peer]'den çeker (onda olanları). Üye başına tek iş.
  Future<void> _pullFiles(DiscoveredPeer peer) {
    final id = peer.info.deviceId;
    if (!_running || target.missingFiles().isEmpty) return Future.value();
    return _filePulls[id] ??= _pullFilesFrom(peer).whenComplete(() => _filePulls.remove(id));
  }

  Future<void> _pullFilesFrom(DiscoveredPeer peer) async {
    final client = _clientFor(peer);
    _fileClients.add(client);
    try {
      for (final e in target.missingFiles().entries) {
        if (!_running) return;
        // Aynı dosya başka bir üyeden iniyorsa ikinci kez yazılmasın.
        if (!_fetching.add(e.key)) continue;
        final temp = target.incomingFile(e.key);
        try {
          final found = await client.downloadFile(
            e.key,
            temp,
            limit: e.value > 0 ? e.value : Attachment.maxBytes,
            // Yüzde değişince haber: büyük videoda saniyede yüzlerce parça gelir.
            onProgress: (received, total) => _setProgress(e.key, (received * 100 ~/ total).clamp(0, 100)),
          );
          if (found && !_closed && await target.adoptFile(e.key, temp)) notifyListeners();
        } finally {
          _setProgress(e.key, null);
          _fetching.remove(e.key);
          // Yarım kalan ya da kabul edilmeyen indirme diskte yer tutmasın.
          if (await temp.exists()) await temp.delete();
        }
      }
    } on Object {
      // Ağ koptu ya da dosya bozuk geldi: bir sonraki eşitlemede yeniden denenir.
    } finally {
      _timeShifts[peer.info.deviceId] = client.timeShift;
      _fileClients.remove(client);
      client.close();
    }
  }

  /// Bu üyenin değişiklikleri sormadan gelsin (bu cihazın kararı).
  Future<void> setTrusted(String deviceId, bool on) async {
    _config = _config.copyWith(
      trusted: on ? {..._config.trusted, deviceId} : ({..._config.trusted}..remove(deviceId)),
    );
    await _save();
    notifyListeners();
  }

  /// Adet ve alışveriş listesi değişiklikleri sormadan gelsin.
  Future<void> setQuickSmall(bool on) async {
    _config = _config.copyWith(quickSmall: on);
    await _save();
    notifyListeners();
  }

  void _onPeersChanged(List<DiscoveredPeer> _) {
    notifyListeners();
    final now = DateTime.now();
    for (final peer in onlineMembers) {
      final last = _lastSyncWith[peer.info.deviceId];
      if (last == null || now.difference(last) > resyncAfter) {
        unawaited(_syncWith(peer));
      }
    }
  }

  void _onLocalChange() {
    if (!_running) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () async {
      // Duyuru da tazelenir: karşı taraf yeni damgayı görüp bir dahaki
      // sefere boşuna eşitlemeye kalkmasın (ya da değiştiğini fark etsin).
      await discovery.announceNow();
      await _syncAll();
    });
  }

  /// İki tarafta da son eşitlemeden beri hiçbir şey değişmediyse envanteri
  /// gidip gelmeye gerek yok. Eksik resmimiz varsa yine konuşulur; damga
  /// yalnızca kayıtları özetler.
  bool _upToDateWith(DiscoveredPeer peer) {
    final last = _syncedStamps[peer.info.deviceId];
    if (last == null || peer.info.stamp.isEmpty) return false;
    if (last.theirs != peer.info.stamp || last.ours != _stamp()) return false;
    return target.missingImages().isEmpty;
  }

  Future<void> _syncAll() async {
    for (final peer in onlineMembers) {
      await _syncWith(peer);
    }
  }

  /// Elle "şimdi eşitle".
  Future<void> syncNow() => _syncAll();

  /// Arka planda kısa bir eşitleme turu (uygulama kapalıyken ya da arka
  /// plandayken): ağ açılır, üyeler aranır, bulunanlarla eşitlenir, sonra eski
  /// haline döner. Sunucu da açık kalır: ötekiler de bize gönderebilsin.
  /// Eşitlenen üye sayısını döner.
  ///
  /// Duraklatma işaretine dokunulmaz: tur sürerken uygulama öne gelirse [resume] işini
  /// görebilsin. Tur boyunca temizlenirken o sırada gelen resume hiçbir şey yapmıyor, tur
  /// bitince ağ kapanıp işaret geri konduğu için uygulama önde, ortak kullanım kapalı
  /// kalıyordu (bir sonraki arka plan / ön plan geçişine kadar).
  Future<int> syncRound({Duration window = const Duration(seconds: 40)}) async {
    if (!_loaded || !_config.enabled || !_config.isShared) return 0;
    final wasRunning = _running;
    final wasPaused = _paused;
    await _start();
    final others = {for (final m in _config.members) if (m.deviceId != _config.deviceId) m.deviceId};
    final synced = <String>{};
    final end = DateTime.now().add(window);
    var lastProbe = DateTime.now();
    try {
      while (_running && DateTime.now().isBefore(end) && !synced.containsAll(others)) {
        for (final peer in onlineMembers) {
          final id = peer.info.deviceId;
          if (!synced.contains(id) && await _syncWith(peer)) synced.add(id);
        }
        if (synced.containsAll(others)) break;
        await Future<void>.delayed(const Duration(seconds: 2));
        // Seyrek duyuruyu beklemeden: ara ara sor.
        if (DateTime.now().difference(lastProbe) > const Duration(seconds: 8)) {
          lastProbe = DateTime.now();
          await discovery.probe();
        }
      }
      // Ekler ayrı işte iniyor: turun kalan süresi kadar beklenir (büyük bir
      // video yetişmezse uygulama açılınca baştan iner).
      final left = end.difference(DateTime.now());
      if (_filePulls.isNotEmpty && left > Duration.zero) {
        await Future.wait(_filePulls.values.toList()).timeout(left, onTimeout: () => const []);
      }
    } finally {
      // Duraklatılmışken başlayan tur sürerken uygulama öne geldiyse ağ açık kalır.
      final resumed = wasPaused && !_paused;
      if (!wasRunning && !resumed) await _stop();
    }
    return synced.length;
  }

  Future<bool> _syncWith(DiscoveredPeer peer, {bool direct = false}) =>
      _tracked(_exchange(peer, direct: direct));

  Future<bool> _exchange(DiscoveredPeer peer, {required bool direct}) async {
    final id = peer.info.deviceId;
    if (!_running || _syncing.contains(id)) return false;
    // Sürüm uyuşmazlığı işaretliyse kısayol yok: güncellendi mi, gerçekten bakılsın.
    if (!direct && !_incompatible.containsKey(id) && _upToDateWith(peer)) {
      _lastSyncWith[id] = DateTime.now();
      // Kayıtlar aynı ama bir ek yarım kalmış olabilir: yalnızca o çekilir.
      unawaited(_pullFiles(peer));
      return true;
    }
    // Farklı veri sürümü: durum alışverişi yok (bkz. kDataVersion). Duyuruda
    // sürüm yoksa karşıdaki uygulama bu kontrolden eski demektir.
    if (peer.info.dataVersion != kDataVersion) {
      _markIncompatible(id, peer.info.dataVersion);
      return false;
    }
    _syncing.add(id);
    notifyListeners();
    final client = _clientFor(peer);
    _syncClients.add(client);
    try {
      final asked = DateTime.now().millisecondsSinceEpoch;
      final remote = await client.getState();
      _checkOpen();
      _noteClock(id, remote, (asked + DateTime.now().millisecondsSinceEpoch) ~/ 2);
      if (remote.dataVersion != kDataVersion) {
        _markIncompatible(id, remote.dataVersion);
        return false;
      }
      // Karşının damgası: duyurusu eski olabilir, gerçekten aldığımız
      // durumdan hesaplanır.
      final theirStamp = '${stateStampOf(remote.nodes.values, remote.tombstones)}'
          '~${memberStampOf(remote.members, remote.removed, remote.governance)}'
          '~${noticeStampOf(remote.notices)}';
      final inventoryId = _config.inventoryId;
      await _mergeState(remote, from: id, direct: direct);
      _checkOpen();
      // Karşının üye listesinden çıkarıldığımızı öğrendik: artık o envanter değiliz.
      if (_config.inventoryId != inventoryId) return false;
      for (final rel in target.missingImages()) {
        final bytes = await client.getImage(rel);
        _checkOpen();
        if (bytes != null) await target.saveImage(rel, bytes);
      }
      // Anlık görüntü ile damgası arasında bekleme yok: araya bir yerel
      // değişiklik girerse onu "gönderilmiş" saymayalım.
      final outgoing = _state();
      final sentStamp = _stamp();
      final theyNeed = await client.postState(outgoing);
      _checkOpen();
      for (final rel in theyNeed) {
        final bytes = await target.readImage(rel);
        if (bytes != null) await client.putImage(rel, bytes);
      }
      // Ekler ayrı bir işte iner (bkz. [_filePulls]); beklenmez.
      unawaited(_pullFiles(peer));
      final now = DateTime.now();
      _lastSyncWith[id] = now;
      // Eksiksiz tamamlandı: bundan sonra iki damga da değişmezse atlanır.
      // (Yarıda kalan eşitlemede damga yazılmaz, bir dahakine tam yapılır.)
      _syncedStamps[id] = (ours: sentStamp, theirs: theirStamp);
      _config = _config.copyWith(
        lastSyncAt: now,
        syncedWith: {..._config.syncedWith, id: now.millisecondsSinceEpoch},
      );
      await _save();
      lastError = null;
      _failures.remove(id);
      if (_incompatible.remove(id) != null) notifyListeners();
      return true;
    } on PeerException catch (e) {
      if (e.incompatible) {
        _markIncompatible(id, e.dataVersion ?? 0);
        return false;
      }
      if (e.removed) {
        await _removedByOthers();
        return false;
      }
      lastError = e.message;
      // Kapanırken kesilen alışveriş bir hata değil.
      if (!_closed) {
        _failures[id] = e.timedOut
            ? SyncFailure.timeout
            : e.unauthorized
                ? SyncFailure.rejected
                : e.unreachable
                    ? SyncFailure.unreachable
                    : (e.status ?? 0) >= 500
                        ? SyncFailure.server
                        : SyncFailure.other;
      }
      return false;
    } finally {
      _timeShifts[id] = client.timeShift;
      _syncClients.remove(client);
      client.close();
      _syncing.remove(id);
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- katılma: sahip

  /// Aynı anda bekletilecek en fazla istek: ağdaki bir cihaz uydurma
  /// kimliklerle sonsuz istek yığmasın.
  static const _maxPendingJoins = 8;

  Future<JoinGrant?> _handleJoin(JoinRequest request) async {
    if (!_config.isAdmin) return null;
    // Zaten üye olan bir cihaz anahtarı tutar; isteğini imzalayabiliyorsa
    // yeniden onay sorulmaz. İmzasızsa (kimliği duyurudan okumuş olabilir)
    // normal onay yolundan geçer.
    if (request.signed && _config.isMember(request.deviceId)) return _grant();

    var pending = _pending.where((p) => p.request.deviceId == request.deviceId).firstOrNull;
    if (pending == null && _pending.length >= _maxPendingJoins) return null;
    if (pending == null) {
      pending = PendingJoin(request);
      _pending.add(pending);
      notifyListeners();
    }
    bool accepted;
    try {
      accepted = await pending._decision.future.timeout(joinWait);
    } on TimeoutException {
      accepted = false;
    }
    _pending.remove(pending);
    notifyListeners();
    if (!accepted || !_running) return null;

    _config = _config.copyWith(
      members: [
        ..._config.members.where((m) => m.deviceId != request.deviceId),
        Member(deviceId: request.deviceId, name: request.name, joinedAt: DateTime.now().millisecondsSinceEpoch),
      ],
    );
    await _save();
    notifyListeners();
    return _grant();
  }

  JoinGrant _grant() => JoinGrant(
        inventoryId: _config.inventoryId,
        inventoryName: inventoryName,
        ownerDeviceId: _config.ownerDeviceId,
        key: _config.key,
        members: _members(),
        governance: _config.governance,
      );

  /// Sahibin ekranındaki karar.
  void decideJoin(PendingJoin pending, bool accept) {
    if (!pending._decision.isCompleted) pending._decision.complete(accept);
  }

  // ---------------------------------------------------------------- katılma: yeni kullanıcı

  /// İsteği gönderir ve sahibin kararını bekler. Kabul edilirse envanter
  /// hemen eşitlenir; bu cihazdaki kayıtlar da ortak envantere eklenir.
  Future<JoinOutcome> requestJoin(DiscoveredPeer peer) async {
    // Ortaklıktaysak isteği imzalarız; karşı taraf üye olduğumuzu böyle
    // doğrular. Yeni cihazda anahtar kendi rastgele anahtarımızdır, imza
    // tutmaz ve istek onaya düşer.
    final client = _clientFor(peer);
    try {
      final grant = await client.join(
        deviceId: _config.deviceId,
        name: displayName(),
        timeout: joinWait + const Duration(seconds: 10),
      );
      if (grant == null) return JoinOutcome.rejected;
      _config = _config.copyWith(
        inventoryId: grant.inventoryId,
        inventoryName: grant.inventoryName,
        ownerDeviceId: grant.ownerDeviceId,
        key: grant.key,
        members: [
          for (final m in grant.members)
            if (m.deviceId != _config.deviceId) m,
          // Katılma anı sahibin verdiği: eski bir çıkarılma izinden yeni olmalı.
          Member(
            deviceId: _config.deviceId,
            name: displayName(),
            joinedAt: grant.members.where((m) => m.deviceId == _config.deviceId).firstOrNull?.joinedAt ?? 0,
          ),
        ],
        removed: const {},
      );
      _config = _config.withGovernance(grant.governance ?? Governance(owner: grant.ownerDeviceId));
      await _save();
      notifyListeners();
      if (_running) await discovery.announceNow();
      final synced = await _syncWith(peer, direct: true);
      if (!synced && _incompatible.containsKey(peer.info.deviceId)) return JoinOutcome.incompatible;
      return JoinOutcome.accepted;
    } on PeerException catch (e) {
      return e.timedOut ? JoinOutcome.timeout : JoinOutcome.unreachable;
    } finally {
      client.close();
    }
  }

  /// Ortaklıktan ayrıl: kayıtlar bu cihazda kalır, artık eşitlenmez. Ana
  /// kullanıcı da sahip de ayrılabilir. Ağdaki üyelere ayrıldığımız son bir
  /// eşitlemeyle bildirilir (listelerinden düşelim); o an ağda olmayanlar bunu
  /// diğerlerinden öğrenir. [successor]: son ana kullanıcı ayrılırken yetkiyi
  /// bıraktığı üye (yoksa katılma isteklerini onaylayan kalmazdı).
  ///
  /// Yönetici ayrılırken yöneticilik [newOwner]'a, verilmezse varise geçer
  /// (arayüz ikisi de yoksa birini seçtirir); varis ayrılırken varislik boşalır.
  /// [deleted]: envanter bu cihazdan siliniyor; diğerlerine öyle haber gider.
  Future<void> leave({String? newOwner, bool deleted = false}) async {
    if (_config.isShared) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_config.isOwner) {
        final next = newOwner != null && _config.isMember(newOwner) ? newOwner : _config.heir;
        if (next != null && next != _config.deviceId) {
          _config = _config.withGovernance(Governance(owner: next, ownerAt: now, heirAt: now));
        }
      } else if (_config.isHeir) {
        _config = _config.withGovernance(Governance(
          owner: _config.ownerDeviceId,
          ownerAt: _config.ownerAt,
          heirAt: now,
        ));
      }
      _config = _config.copyWith(
        members: [for (final m in _config.members) if (m.deviceId != _config.deviceId) m],
        removed: {..._config.removed, _config.deviceId: now},
      );
      await _tellOthers(deleted ? 'deleted' : 'left');
    }
    await _resetToOwn();
  }

  /// Ayrılırken ağdaki üyelere son durumu (üye listesi, ayrılma izi, yeni
  /// yönetici ve veda) gönderir; yanıt vermeyen beklenmez, başkalarından öğrenir.
  Future<void> _tellOthers(String farewell) async {
    final s = _state();
    final state = SyncState(
      nodes: s.nodes,
      tombstones: s.tombstones,
      members: s.members,
      removed: s.removed,
      governance: s.governance,
      farewell: farewell,
      from: s.from,
    );
    await Future.wait([for (final peer in onlineMembers) _post(peer, state)]);
  }

  /// Kendi envanterine dön: yeni kimlik ve anahtar, üye yalnızca bu cihaz.
  Future<void> _resetToOwn() async {
    _syncedStamps.clear();
    _config = SharingConfig.fresh(
      deviceId: _config.deviceId,
      inventoryName: _config.isOwner ? _config.inventoryName : '',
      enabled: _config.enabled,
      autoAccept: _config.autoAccept,
    );
    await _save();
    _lastSyncWith.clear();
    if (_running) await discovery.announceNow();
    notifyListeners();
  }
}
