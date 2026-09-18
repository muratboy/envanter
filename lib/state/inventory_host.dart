import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/app_paths.dart';
import '../core/strings.dart';
import '../core/text_match.dart';
import '../data/database.dart';
import '../data/library.dart';
import '../data/node.dart';
import '../services/auto_backup.dart';
import '../services/closed_sync.dart';
import '../services/date_notifier.dart';
import '../services/platform_bridge.dart';
import '../sync/clock.dart';
import '../sync/discovery.dart';
import '../sync/fields.dart';
import '../sync/sharing_config.dart';
import '../sync/sharing_service.dart';
import 'inventory_store.dart';

const _uuid = Uuid();

/// Açık envanter: mağazası ve ortak kullanımı.
class InventorySession {
  InventorySession(this.id, this.store, this.sharing);

  final String id;
  final InventoryStore store;
  final SharingService sharing;

  /// Arkadan yükleme (mağaza + ortak kullanım) bitince tamamlanır. Envanter
  /// kapanmadan önce beklenir: hızlı art arda geçişte veritabanı yükleme
  /// ortasında kapanmasın.
  Future<void> ready = Future.value();
}

/// Envanterler arasında geçiş (Obsidian'daki kasalar gibi). Aynı anda tek
/// envanter açıktır: geçerken açık olanın ortak kullanımı durur, veritabanı
/// kapanır, ötekisi açılır ve arayüz baştan (yeni gezginle, ana ekrandan)
/// çizilir. Kapalı envanterler eşitlenmez; açılınca kaldığı yerden devam eder.
class InventoryHost extends ChangeNotifier {
  InventoryHost(this.library, {this.makeSharing});

  final InventoryLibrary library;

  /// Testler ortak kullanımı kendi ağ ayarlarıyla (loopback, rastgele port) kurar.
  final SharingService Function(InventoryStore store, String Function() displayName)? makeSharing;
  InventorySession? _session;
  bool _busy = false;

  /// Envanterden çıkarken yedek yazılıyor (arayüz bekleme gösterir).
  bool backingUp = false;

  /// [backupAll] sürüyor: (biten, toplam).
  (int, int)? backupAllProgress;

  /// Yedeği eksik kapalı envanterler (otomatik yedek açıkken).
  List<InventoryEntry> get unbackedEntries => [
        if (_session?.store.settings.autoBackupUri != null)
          for (final e in library.entries)
            if (e.id != _session?.id && e.needsBackup) e,
      ];

  /// Yedeği eksik kapalı envanterleri sırayla açıp kapatır (kapanırken
  /// yedeklenir), sonra açık olana döner. Otomatik yedek ilk açıldığında:
  /// yoksa açılmayan envanter hiç yedeklenmezdi.
  Future<void> backupAll() async {
    final start = _session?.id;
    final todo = [for (final e in unbackedEntries) e.id];
    if (start == null || todo.isEmpty || backupAllProgress != null) return;
    backupAllProgress = (0, todo.length);
    notifyListeners();
    try {
      for (final (i, id) in todo.indexed) {
        await open(id);
        await _session?.ready;
        backupAllProgress = (i, todo.length);
        notifyListeners();
      }
      await open(start);
    } finally {
      backupAllProgress = null;
      notifyListeners();
    }
  }

  /// Kayıtları (ve altındakileri) başka bir envantere taşır veya kopyalar.
  /// [isCopy] true ise kaynakta kalır, false ise kaynaktan kalıcı silinir ("Son silinenler"de 30 gün durur).
  ///
  /// Kopyada her kayıt yeni kimlik alır; taşımada kimlik kalır (basılı QR etiketi yeni yerinde de
  /// çalışsın). Hedefe "INSERT OR REPLACE" ile yazılırken aynı klasörün ikinci kopyası öncekinin
  /// üstüne yazılıyor, hedefte o arada içine eklenenler ON DELETE CASCADE ile siliniyordu.
  Future<int> transferNodes({
    required List<Node> nodes,
    required String targetInventoryId,
    required bool isCopy,
  }) async {
    final session = _session;
    if (session == null || nodes.isEmpty) return 0;
    if (session.id == targetInventoryId) return 0;
    // Hedef o an arka planda eşitleniyor olabilir: veritabanını önce o bıraksın.
    await ClosedSync.stop();

    final store = session.store;
    final sourceDocs = library.docsOf(session.id);
    final targetDocs = library.docsOf(targetInventoryId);

    // Taşınacak tüm kayıtları topla (altındakilerle birlikte)
    final allNodes = <String, Node>{};
    void collect(Node n) {
      allNodes[n.id] = n;
      if (n.isContainer) {
        for (final child in store.childrenOf(n.id)) {
          collect(child);
        }
      }
    }

    for (final n in nodes) {
      collect(n);
    }

    final ids = {for (final id in allNodes.keys) id: isCopy ? _uuid.v4() : id};
    final now = SyncClock.now();
    final written = <Node>[];
    for (final n in allNodes.values) {
      // Fotoğrafı ve ekleri kopyala (aynı göreli yolla: kayıt onları bu adla gösterir)
      for (final rel in [?n.imagePath, for (final a in n.attachments) ?a.file]) {
        final src = File(p.join(sourceDocs, rel));
        if (src.existsSync()) {
          final dst = File(p.join(targetDocs, rel));
          dst.parent.createSync(recursive: true);
          src.copySync(dst.path);
        }
      }
      // Üst klasörü aktarılanlar içinde değilse hedefte kök seviyeye geçer. "Ayşe'de" ve sorumlular kaynağın
      // ortak kullanımına ait, kaybolduğu yer de oradaki bir klasör: hedefte karşılıkları yok.
      final root = n.parentId == null || !allNodes.containsKey(n.parentId);
      final row = n.toMap()
        ..['id'] = ids[n.id]
        ..['parent_id'] = root ? null : ids[n.parentId]
        ..['held_by'] = null
        ..['managers'] = null
        ..['lost_from'] = ids[n.lostFrom];
      // Hedefte yeni bir kayıt gibi bütün alanlar şimdiye damgalanır (restorePurged gibi): taşınıp geri
      // gelen kayıt oradaki eski silme izine ya da başka cihazdaki eski kopyasına yenilmesin.
      written.add(stampChanges(null, Node.fromMap(row).copyWith(updatedAt: now, updatedBy: store.authorId), now));
    }

    final targetDb = await AppDatabase.openDatabaseAt(library.dbPathOf(targetInventoryId));
    try {
      await AppDatabase.writeInto(targetDb, written);
    } finally {
      await targetDb.close();
    }

    // Hedef envanterin özeti ve arama dizini: dizin o envanter kapanırken baştan yazılır, o zamana dek
    // aktarılanlar eklenir (kapalı envanterde arama ve taşınan kutunun QR etiketi de bulsun).
    final targetEntry = library.byId(targetInventoryId);
    if (targetEntry != null) {
      await library.update(targetEntry.copyWith(
        count: targetEntry.count + written.length,
        unbacked: targetEntry.unbacked + written.length,
      ));
    }
    final index = library.readIndex(targetInventoryId);
    if (index != null) {
      final s = store.strings;
      String placeOf(Node n) {
        final parts = <String>[];
        var top = n;
        for (var up = allNodes[n.parentId]; up != null; up = allNodes[up.parentId]) {
          parts.insert(0, store.nameOf(up));
          top = up;
        }
        return [top.isLost ? s.lostDrawer : (top.inDrawer ? s.drawer : s.home), ...parts].join(' / ');
      }

      final fresh = ids.values.toSet();
      await library.writeIndex(targetInventoryId, [
        for (final r in index)
          if (!fresh.contains(r.id)) r,
        for (final n in allNodes.values) store.indexRecord(n, id: ids[n.id], path: placeOf(n)),
      ]);
    }

    // Kopyalama değil taşımaysa kaynaktan kalıcı sil
    if (!isCopy) {
      for (final n in nodes) {
        await store.deleteForever(n.id);
      }
    }

    notifyListeners();
    return written.length;
  }

  /// Veritabanı açılamayan envanterin adı: bozuk dosya Silinenler'e alındı,
  /// envanter boş açıldı. Arayüz bir kez söyler ([takeRecovery]).
  String? _recovered;

  String? takeRecovery() {
    final r = _recovered;
    _recovered = null;
    return r;
  }

  /// Silinmek üzere açılan (paylaşılan) envanter: açılınca arayüz önce
  /// diğerlerine haber verip sonra siler ([takePendingDelete]).
  String? _pendingDelete;

  String? takePendingDelete() {
    final id = _pendingDelete;
    if (id == null || id != _session?.id) return null;
    _pendingDelete = null;
    return id;
  }

  /// Başka envantere geçilince yeni arayüzün yapacağı iş: bir kaydı göstermek
  /// (aramadan ya da QR'dan) ya da alışveriş listesini açmak.
  Arrival? _arrival;

  Arrival? takeArrival() {
    final a = _arrival;
    if (a == null || a.inventoryId != _session?.id) return null;
    _arrival = null;
    return a;
  }

  Future<void> openAt(String id, Arrival arrival) async {
    _arrival = arrival;
    await open(id);
  }

  /// Kapalı envanterlerin dizinleri; dosya değişmedikçe yeniden okunmaz.
  final Map<String, (DateTime, List<IndexedRecord>?)> _indexes = {};

  List<IndexedRecord>? _indexOf(String id) {
    final file = library.indexFileOf(id);
    final at = file.existsSync() ? file.lastModifiedSync() : DateTime(0);
    final cached = _indexes[id];
    if (cached != null && cached.$1 == at) return cached.$2;
    final records = library.readIndex(id);
    _indexes[id] = (at, records);
    return records;
  }

  /// Açık olmayan envanterlerde arama (açık olanınki mağazada). Sıralama
  /// mağazadaki gibi: adı tam eşleşen, adı böyle başlayan, bütün kelimeleri
  /// adında geçen, yalnızca notunda ya da yerinde geçen.
  List<OtherHit> searchOthers(String query) {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return const [];
    final whole = tokens.join(' ');
    final hits = <(OtherHit, int)>[];
    for (final e in library.entries) {
      if (e.id == _session?.id) continue;
      for (final r in _indexOf(e.id) ?? const <IndexedRecord>[]) {
        final name = foldForSearch(r.name);
        final rest = [
          foldForSearch(r.place),
          foldForSearch(r.note),
          for (final a in r.attachments) foldForSearch(a),
          if (r.barcode != null) foldForSearch(r.barcode!),
        ].join('\n');
        if (!tokens.every((t) => name.contains(t) || rest.contains(t))) continue;
        final rank = name == whole ? 0 : name.startsWith(whole) ? 1 : tokens.every(name.contains) ? 2 : 3;
        hits.add((OtherHit(entry: e, record: r), rank));
      }
    }
    hits.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.record.name.compareTo(b.$1.record.name));
    return [for (final h in hits) h.$1];
  }

  /// Aranamayan (hiç açılıp kapanmamış, dizini olmayan) kapalı envanterler.
  List<InventoryEntry> get unindexed => [
        for (final e in library.entries)
          if (e.id != _session?.id && e.count > 0 && _indexOf(e.id) == null) e,
      ];

  /// QR'daki kayıt açık olmayan bir envanterde mi.
  InventoryEntry? findInOthers(String recordId) {
    for (final e in library.entries) {
      if (e.id == _session?.id) continue;
      if (_indexOf(e.id)?.any((r) => r.id == recordId) ?? false) return e;
    }
    return null;
  }

  /// Barkodu açık olmayan bir envanterde arar (kapanırken yazılan dizinden).
  OtherHit? findBarcodeInOthers(String code) {
    for (final e in library.entries) {
      if (e.id == _session?.id) continue;
      for (final r in _indexOf(e.id) ?? const <IndexedRecord>[]) {
        if (r.barcode == code) return OtherHit(entry: e, record: r);
      }
    }
    return null;
  }

  /// Paylaşılan kapalı bir envanteri silmek için: önce açılır, haber verme ve
  /// yönetici seçimi orada yapılır.
  Future<void> openToDelete(String id) async {
    _pendingDelete = id;
    await open(id);
    notifyListeners();
  }

  InventorySession get session => _session!;

  /// Arayüzün baştan çizilmesi için: aynı envanter yeniden açılsa da değişir.
  int generation = 0;

  /// Başka birinin envanterine yeni bir envanter olarak katılma sürüyor:
  /// kimin onayı bekleniyor. Arayüz (geçişte baştan kurulan) bunu görüp
  /// bekleme penceresini gösterir.
  String? joiningOwner;

  /// Son katılma denemesinin sonucu; arayüz bir kez gösterip [takeJoinResult] ile alır.
  ({String inventory, JoinOutcome outcome})? _joinResult;

  ({String inventory, JoinOutcome outcome})? takeJoinResult() {
    final r = _joinResult;
    _joinResult = null;
    return r;
  }

  /// Ağdaki bir envantere, bu cihazdaki kayıtları karıştırmadan katılır: boş
  /// bir envanter açılır, istek oradan gönderilir. Kabul edilmezse boş kalan
  /// envanter silinir, önceki açılır.
  Future<JoinOutcome> joinAsNew(DiscoveredPeer peer, {required String owner}) async {
    final previous = _session?.id;
    final name = peer.info.inventoryName.trim().isEmpty ? owner : peer.info.inventoryName.trim();
    final entry = await library.create(name);
    joiningOwner = owner;
    await open(entry.id);
    var outcome = JoinOutcome.unreachable;
    try {
      await session.ready;
      await session.sharing.setEnabled(true);
      outcome = await session.sharing.requestJoin(peer);
    } finally {
      joiningOwner = null;
      _joinResult = (inventory: name, outcome: outcome);
    }
    // Olmadıysa boş kalan envanter silinir; sonucu önceki envanterin (yeniden
    // kurulan) arayüzü gösterir.
    if (outcome != JoinOutcome.accepted && previous != null && session.store.totalRecordCount == 0) {
      await open(previous);
      await library.delete(entry.id);
      await library.purge(entry.id); // boş bir deneme: Silinenler'de beklemesine gerek yok
    }
    notifyListeners();
    return outcome;
  }

  /// Açılışta: en son açık olan envanter.
  Future<void> start() => _open(library.activeId);

  /// Başka bir envantere geçer.
  Future<void> open(String id) async {
    if (_busy || id == _session?.id || library.byId(id) == null) return;
    _busy = true;
    try {
      // Arka planda o envanter eşitleniyor olabilir: veritabanını önce o bıraksın.
      await ClosedSync.stop();
      await _close();
      await _open(id);
    } finally {
      _busy = false;
    }
  }

  /// Sıfırdan boş bir envanter kurar ve ona geçer.
  Future<InventoryEntry> create(String name) async {
    final entry = await library.create(name);
    await open(entry.id);
    return entry;
  }

  Future<void> rename(String id, String name) async {
    final entry = library.byId(id);
    if (entry == null) return;
    await library.update(entry.copyWith(name: name.trim()));
    // Paylaşan sahipse ağda görünen adı da bu olsun.
    final sharing = _session?.sharing;
    if (id == _session?.id && sharing != null && sharing.config.isOwner) await sharing.rename(name.trim());
    notifyListeners();
  }

  /// Envanterin rengi (null: seçilmemiş, varsayılan görünüm). Renk ve amblem
  /// ayrı ayrı, **o anki** kayıt üzerinden yazılır: arayüz ikisini birlikte
  /// verseydi, art arda iki dokunuşta ikincisi eski kayıttaki değeri geri yazardı.
  Future<void> setColor(String id, int? color) =>
      _setLook(id, (e) => e.copyWith(color: color, clearColor: color == null));

  /// Envanterin amblemi (simge anahtarı; null: varsayılan kutu).
  Future<void> setGlyph(String id, String? glyph) =>
      _setLook(id, (e) => e.copyWith(glyph: glyph, clearGlyph: glyph == null));

  Future<void> _setLook(String id, InventoryEntry Function(InventoryEntry e) change) async {
    final entry = library.byId(id);
    if (entry == null) return;
    // Kayıt bellekte hemen değişir; arayüz dosyanın yazılmasını beklemesin.
    final saved = library.update(change(entry));
    notifyListeners();
    await saved;
  }

  /// Envanteri Silinenler'e taşır ([InventoryLibrary.keepDeleted] boyunca geri
  /// getirilebilir). Açık olansa önce en son açılan başka envantere geçilir,
  /// hiç yoksa boş bir envanter açılır. Kişinin kendi fotoğrafı yerinde kalır.
  /// Paylaşılıyorsa diğerlerine haber vermek çağıranın işi (ayrılma akışı).
  Future<bool> delete(String id) async {
    if (library.byId(id) == null) return false;
    // Dosyaları taşınacak envanter arka planda açık kalmasın.
    await ClosedSync.stop();
    final avatar = _session?.store.settings.userAvatarPath;
    if (id == _session?.id) {
      final others = [...library.entries.where((e) => e.id != id)]
        ..sort((a, b) => (b.openedAt ?? b.createdAt).compareTo(a.openedAt ?? a.createdAt));
      if (others.isEmpty) {
        final fresh = await library.create('');
        await open(fresh.id);
      } else {
        await open(others.first.id);
      }
    }
    final ok = await library.delete(id, keep: {?avatar});
    if (ok) notifyListeners();
    return ok;
  }

  Future<void> restoreDeleted(String id) async {
    if (await library.restore(id)) notifyListeners();
  }

  Future<void> purgeDeleted(String id) async {
    await library.purge(id);
    notifyListeners();
  }

  /// Envanterin görünen adı; ilk envanterin adı boşsa uygulamanın adı.
  String nameOf(InventoryEntry entry, AppStrings s) => library.nameOf(entry, s.appTitle);

  /// Birden çok envanter varken bildirim, widget ve yedek adlarına eklenen ad.
  String? labelFor(AppStrings s) => library.labelFor(s.appTitle);

  /// Açılamayan veritabanı kenara alınır (Silinenler'e ayrı bir kopya olarak,
  /// geri getirilince yeniden denenir), envanter boş açılır; arayüz yedekten
  /// geri yüklemeyi önerir. Uygulama açılamaz hale gelmesin.
  Future<void> _recover(String id) async {
    final entry = library.byId(id);
    final s = AppStrings.forLanguage(switch (library.global['language']) {
      'turkish' => AppLanguage.turkish,
      'english' => AppLanguage.english,
      _ => AppLanguage.system,
    });
    final name = entry == null ? s.appTitle : (entry.name.trim().isEmpty ? s.appTitle : entry.name.trim());
    await AppDatabase.instance.close();
    await library.quarantineDatabase(id, s.unopenedCopy(name));
    await AppDatabase.instance.openAt(library.dbPathOf(id));
    _recovered = name;
  }

  Future<void> _open(String id) async {
    try {
      await AppDatabase.instance.openAt(library.dbPathOf(id));
    } on Object {
      await _recover(id);
    }
    AppPaths.useDirectory(library.docsOf(id));
    final store = InventoryStore();
    String displayName() {
      final name = store.settings.userName.trim();
      return name.isEmpty ? store.strings.user : name;
    }

    final sharing = makeSharing?.call(store, displayName) ??
        SharingService(
          target: store,
          configStore: MetaSharingConfigStore(),
          displayName: displayName,
          setMulticastLock: PlatformBridge.setMulticastLock,
        );
    final session = _session = InventorySession(id, store, sharing);
    await library.setActive(id);
    generation++;
    notifyListeners();
    // Ekran hemen, veri arkadan. Ortak kullanım envanter yüklendikten sonra
    // başlar: karşıdan gelen veri boş bir envanterle birleşmesin.
    session.ready = () async {
      try {
        await store.init();
      } on Object {
        await _recover(id);
        await store.init();
        notifyListeners();
      }
      await sharing.load();
      wire(store, sharing);
    }();
  }

  /// Mağaza ile ortak kullanımı birbirine bağlar (ortak kullanım yüklendikten
  /// sonra). Açık envanterde de, arka planda eşitlenen kapalı envanterde de
  /// (`ClosedSync`) aynı kurallar geçerli olsun diye tek yerde.
  static void wire(InventoryStore store, SharingService sharing) {
    // Düzenlemeler bu kimlikle imzalanır; karşıda "kim yaptı" görünür.
    store.authorId = sharing.config.deviceId;
    // Yetkili (ana kullanıcı) değişiklikleri onay beklemez.
    store.isAdmin = (id) => sharing.config.isAdminDevice(id);
    store.isTrusted = (id) => sharing.config.trusted.contains(id);
    store.acceptsSmall = () => sharing.config.quickSmall;
    store.onRejected = sharing.addNotices;
    // Özel alana giren kayıt karşıya gitmiş mi: son eşitlemeden önce var mıydı.
    store.lastSyncAt = () => sharing.config.isShared ? sharing.config.lastSyncAt : null;
  }

  /// Envanter kapalıyken de gösterilecek bilgiler: kayıt sayısı, paylaşılıyor
  /// mu, yedeği, alışveriş listesi, yaklaşan tarih bildirimleri, onay bekleyenler.
  /// [label]: birden çok envanter varken bildirim satırlarına eklenen ad.
  static InventoryEntry summarize(InventoryEntry entry, InventoryStore store, SharingService sharing, String? label) =>
      entry.copyWith(
        count: store.totalRecordCount,
        shared: sharing.config.isShared,
        backedUpAt: store.settings.lastBackupAt,
        unbacked: store.changesSinceBackup,
        backupKnown: true,
        shopping: store.savedShopping(),
        pending: store.pendingCount,
        // Bildirimi kapalı envanterin satırı saklanmaz (her envanterin kendi ayarı).
        alerts: store.settings.dateNotifications
            ? DateNotifier.snapshot(store, label: label, now: DateTime.now(), maxDays: 366)
            : const [],
      );

  /// Kapalı bir envanterin özeti dışarıdan (arka plan eşitlemesi) yenilendi.
  void summaryChanged() => notifyListeners();

  /// Arka plan işinin sonunda: açık envanter kapanır (kapanış işleriyle:
  /// yedek, dizin, kayıt sayısı), veritabanı bırakılır.
  Future<void> stop() async {
    await _close();
    _session = null;
    await AppDatabase.instance.close();
  }

  /// Açık envanteri bırakır: ağ durur, bekleyen yazımlar biter, kapalıyken de
  /// gösterilecek bilgiler (kayıt sayısı, yaklaşan tarih bildirimleri) saklanır.
  Future<void> _close() async {
    final session = _session;
    if (session == null) return;
    final store = session.store;
    try {
      await session.ready;
    } on Object {
      // Yüklenemediyse de kapatılır.
    }
    await session.sharing.shutdown();
    store.close();
    await store.settle();
    AutoBackup.closing = store;
    await AutoBackup.settle();
    // Değişen envanter kapanırken yedeklenir (otomatik yedek açıksa): kapalı
    // envanter değişmediği için son yedeği hep güncel kalır, açılmayan
    // envanter de yedeksiz kalmaz.
    if (!store.loading && store.settings.autoBackupUri != null && store.changesSinceBackup > 0) {
      backingUp = true;
      notifyListeners();
      try {
        await AutoBackup.run(store);
      } finally {
        backingUp = false;
        notifyListeners();
      }
    }
    final entry = library.byId(session.id);
    if (entry != null && !store.loading) {
      final s = store.strings;
      // Öteki envanter açıkken de aranabilsin, QR'ı bulunabilsin.
      try {
        await library.writeIndex(session.id, store.searchIndex());
      } on Object {
        // Dizin yazılamazsa yalnızca kapalıyken arama eksik kalır.
      }
      await library.update(summarize(entry, store, session.sharing, labelFor(s)));
    }
    // Eski arayüz bir sonraki karede ağaçtan çıkar; dinleyicileri ondan sonra.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      session.sharing.dispose();
      store.dispose();
    });
  }
}

/// Başka envantere geçince yapılacak iş. [recordId] varsa o kayıt gösterilir
/// ([inside]: klasörse içi açılır, QR'daki gibi); [shopping] alışveriş listesi;
/// [changes] onay bekleyen değişiklikler (bildirime dokunulunca).
class Arrival {
  const Arrival(this.inventoryId, {this.recordId, this.inside = false, this.shopping = false, this.changes = false, this.dates = false});

  final String inventoryId;
  final String? recordId;
  final bool inside;
  final bool shopping;
  final bool changes;
  final bool dates;
}

/// Açık olmayan bir envanterde bulunan kayıt.
class OtherHit {
  const OtherHit({required this.entry, required this.record});

  final InventoryEntry entry;
  final IndexedRecord record;
}

/// Arayüzün envanter listesine ve geçişe ulaştığı yer. Testlerde (tek
/// envanterle doğrudan kurulan uygulamada) yoktur; o zaman liste gizlenir.
class LibraryScope extends InheritedNotifier<InventoryHost> {
  const LibraryScope({super.key, required InventoryHost host, required super.child}) : super(notifier: host);

  static InventoryHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LibraryScope>()?.notifier;

  static InventoryHost? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LibraryScope>()?.notifier;
}
