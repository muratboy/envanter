import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../core/app_paths.dart';
import '../core/money.dart';
import '../core/palette.dart';
import '../core/strings.dart';
import '../core/text_match.dart';
import '../core/time_span.dart';
import '../services/date_alerts.dart';
import '../services/image_service.dart';
import '../services/visual_index.dart';
import '../sync/clock.dart';
import '../sync/fields.dart';
import '../sync/merge.dart';
import '../sync/review.dart';
import '../sync/sync_target.dart';
import '../sync/wire.dart';
import '../data/database.dart';
import '../data/library.dart';
import '../data/lots.dart';
import '../data/node.dart';
import '../data/settings.dart';

const _uuid = Uuid();

/// Fotoğrafların ve ek dosyalarının kapladığı yer (bkz. [InventoryStore.measureStorage]).
class StorageUsage {
  const StorageUsage({
    required this.photoCount,
    required this.photoBytes,
    required this.fileCount,
    required this.fileBytes,
    required this.largest,
  });

  /// Listede gösterilen en büyük ek sayısı.
  static const listed = 30;

  final int photoCount;
  final int photoBytes;
  final int fileCount;
  final int fileBytes;

  /// En büyük ek dosyaları, büyükten küçüğe.
  final List<StoredAttachment> largest;

  int get totalBytes => photoBytes + fileBytes;
}

/// Diskteki bir ek dosyası: hangi kayıtta, kaç bayt.
class StoredAttachment {
  const StoredAttachment({required this.node, required this.attachment, required this.bytes});

  final Node node;
  final Attachment attachment;
  final int bytes;
}

/// Sanal kök kimlikleri: ana ekran, "yeri belli değil" çekmecesi ve
/// yerinde bulunamayanların kayıp çekmecesi.
class Roots {
  static const home = '__home__';
  static const drawer = '__drawer__';
  static const lost = '__lost__';

  static bool isVirtual(String id) => id == home || id == drawer || id == lost;
}

/// Yetkili birinin (ana kullanıcı ya da o klasörün sorumlusu) yaptığı,
/// onay beklemeden uygulanan değişiklikler.
class AuthorityEvent {
  const AuthorityEvent({required this.author, required this.count});

  final String author;
  final int count;
}

/// Başka bir cihazdan gelen kayıp bildirimi ya da bulunma haberi.
/// Kalıcı silinmiş, henüz geri getirilebilen bir kayıt.
class PurgedRecord {
  const PurgedRecord({required this.node, required this.at, required this.inside});

  final Node node;
  final DateTime at;

  /// Onunla birlikte silinen içindekiler.
  final int inside;
}

class LostEvent {
  const LostEvent({required this.node, required this.found, this.by});

  final Node node;

  /// false: kayıp bildirildi; true: biri yerini buldu.
  final bool found;
  final String? by;
}

/// Tum ağacı bellekte tutan tek kaynak. Ev envanteri olceginde (yuzler,
/// birkac bin kayıt) bu en hızlı ve ağaç islemlerini en kolay yol.
class InventoryStore extends ChangeNotifier implements SyncTarget {
  final Map<String, Node> _byId = {};

  /// Kalıcı silinen kayıtların izi (kimlik → zaman, ms). Dosyayla
  /// paylaşımda eski kopyaların silineni geri getirmesini engeller.
  final Map<String, int> _tombstones = {};

  bool loading = true;
  AppSettings settings = const AppSettings();

  /// Metinler ayarlardaki dile göre; değişince tum ağaç tazeleniyor.
  AppStrings strings = AppStrings.forLanguage(AppLanguage.system);

  /// Suruklenmekte olan kart; bırakma hedefleri buna göre isaretlenir.
  String? draggingId;

  Future<void> init() async {
    final nodes = await AppDatabase.instance.loadAll();
    _byId
      ..clear()
      ..addEntries(nodes.map((n) => MapEntry(n.id, n)));
    _invalidate();
    _tombstones
      ..clear()
      ..addAll(await AppDatabase.instance.loadTombstones());
    settings = await AppSettings.load();
    _expiryMemo = Expando();
    strings = AppStrings.forLanguage(settings.language);
    await _loadPending();
    await _loadPurged();
    await _loadHeld();
    _knownPrivate = {..._privateSet};
    _sweepPartials();
    loading = false;
    notifyListeners();
  }

  /// Yarım kalmış ek indirmeleri (uygulama indirme sürerken kapandıysa): eki
  /// bu arada kaldırılmış bir video diskte sonsuza dek yer tutmasın. Yarıda kesilen
  /// yedek aktarmasının parçaları da burada gider (fotoğraflarınki `images/` altında).
  void _sweepPartials() {
    if (!AppPaths.isSet) return;
    try {
      for (final sub in const ['files', 'images']) {
        final dir = Directory(AppPaths.abs(sub));
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync()) {
          if (f is File && f.path.endsWith('.part')) f.deleteSync();
        }
      }
    } on FileSystemException {
      // Silinemezse bir dahaki açılışta denenir.
    }
  }

  // ---------------------------------------------------------------- okuma

  Node? byId(String? id) => id == null ? null : _byId[id];

  /// Kart üzerinde gösterilecek ad; adsız eşyalar için dile uygun etiket.
  String nameOf(Node node) => node.hasName ? node.trimmedName : strings.unnamed;

  bool _visible(Node n) => !n.isDeleted;

  /// Üst kayıt → çocukları (çöptekiler dahil). Kartlar her karede yeniden
  /// çizildiği için ağaç her sorguda baştan taranmasın: bir kez indekslenir,
  /// ağaç değişince düşer.
  Map<String?, List<Node>>? _childIndex;

  /// Seviye → sıralanmış görünür kayıtlar ([childrenOf] sonucu).
  final Map<String, List<Node>> _levelCache = {};

  Map<String?, List<Node>> get _children {
    final cached = _childIndex;
    if (cached != null) return cached;
    final index = <String?, List<Node>>{};
    for (final n in _byId.values) {
      (index[n.parentId] ??= <Node>[]).add(n);
    }
    return _childIndex = index;
  }

  /// Ağaç değişti: indeks ve ondan türeyen her şey baştan hesaplanacak.
  /// [_byId] her değiştiğinde çağrılır (haber vermeden önce de: iki arada
  /// bir sorgu gelirse eski listeyi görmesin).
  void _invalidate() {
    _childIndex = null;
    _buriedCache = null;
    _levelCache.clear();
    _displayCache.clear();
    _coverCache.clear();
    _valueCache.clear();
    _valueRanking = null;
    _barcodeIndex = null;
    _stampCache = null;
    _backupDueCache = null;
    _privateCache = null;
    _datesCache = null;
  }

  /// Klasörler önce, eşyalar sonra; her grup kendi sırasında. Ayarlardan
  /// gruplama kapatılırsa hepsi tek sırada, kullanıcının verdiği sırayla.
  List<Node> _sorted(Iterable<Node> nodes) => nodes.toList()..sort(_deckOrder);

  int _deckOrder(Node a, Node b) {
    if (settings.groupKinds && a.isContainer != b.isContainer) {
      return a.isContainer ? -1 : 1;
    }
    final c = a.sortIndex.compareTo(b.sortIndex);
    return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
  }

  /// [parentId] sanal bir kök ([Roots]) ya da gercek bir klasör kimliği.
  ///
  /// Dönen liste önbellekte tutulur: değiştirilmemeli, gerekiyorsa kopyası
  /// alınmalı (bkz. [reorder]).
  List<Node> childrenOf(String parentId) => _levelCache[parentId] ??= _childrenOf(parentId);

  List<Node> _childrenOf(String parentId) {
    if (Roots.isVirtual(parentId)) {
      final roots = _children[null] ?? const <Node>[];
      if (parentId == Roots.lost) {
        // En son kaybolan en üstte.
        return roots.where((n) => _visible(n) && n.isLost).toList()
          ..sort((a, b) => b.lostAt!.compareTo(a.lostAt!));
      }
      final inDrawer = parentId == Roots.drawer;
      return _sorted(roots.where((n) => _visible(n) && !n.isLost && n.inDrawer == inDrawer));
    }
    return _sorted((_children[parentId] ?? const <Node>[]).where(_visible));
  }

  Map<String, List<Node>>? _barcodeIndex;

  /// Bu barkodu taşıyan görünür kayıtlar (aynı üründen iki yerde olabilir).
  /// Okutunca aranır; dizin bir kez kurulur, ağaç değişince düşer.
  List<Node> byBarcode(String code) {
    final index = _barcodeIndex ??= () {
      final map = <String, List<Node>>{};
      for (final n in _byId.values) {
        final b = n.barcode;
        if (b != null && isLive(n)) (map[b] ??= <Node>[]).add(n);
      }
      return map;
    }();
    return index[code.trim()] ?? const <Node>[];
  }

  /// Kapakta en çok bu kadar fotoğraf durur.
  static const int coverSize = 3;

  /// Kapak aranırken en çok bu kadar kayda bakılır: binlerce fotoğrafsız kayıt
  /// tutan bir klasörün kartı her değişiklikte bütün alt ağacı taramasın.
  static const int _coverScan = 240;

  final Map<String, List<Node>> _coverCache = {};

  /// Fotoğrafı olmayan klasörün kapağı: içindeki fotoğraflı ilk kayıtlar
  /// (en çok [coverSize]). Önce klasörün kendi seviyesi, yetmezse alt klasörler
  /// sırayla: yalnızca klasör tutan bir "Mutfak" da içini göstersin. Klasöre
  /// girmeden içinde ne olduğu görünsün diye; kartlar her karede çizildiği
  /// için önbellekte durur. Dönen liste paylaşılır: değiştirme.
  List<Node> coverOf(String folderId) => _coverCache[folderId] ??= _coverOf(folderId);

  List<Node> _coverOf(String folderId) {
    final found = <Node>[];
    final queue = <String>[folderId];
    var seen = 0;
    for (var i = 0; i < queue.length && found.length < coverSize && seen < _coverScan; i++) {
      for (final n in childrenOf(queue[i])) {
        if (++seen > _coverScan) break;
        if (n.imagePath != null && n.imagePath!.isNotEmpty) {
          found.add(n);
          if (found.length == coverSize) break;
        }
        if (n.isContainer) queue.add(n.id);
      }
    }
    return found.isEmpty ? const <Node>[] : found;
  }

  final Map<String, MoneyTotals> _valueCache = {};

  /// Klasörün (ya da sanal kökün) içindekilerin değeri, bütün alt ağaç: fiyatı olan her
  /// eşyanın fiyatı × adedi, para birimi birim birim (kur çevrimi yok). Klasörün kendi fiyatı
  /// sayılmaz (bkz. [Node.price]). Odak katmanı ve değer sayfası her çizimde sorduğu için
  /// önbellekte durur; ağaç ya da bir kayıt değişince düşer. Paylaşılır: değiştirme.
  MoneyTotals valueOf(String id) => _valueCache[id] ??= _valueOf(id);

  MoneyTotals _valueOf(String id) {
    final total = MoneyTotals();
    if (id == _allRoot) {
      for (final root in const [Roots.home, Roots.drawer, Roots.lost]) {
        total.addAll(valueOf(root));
      }
      return total;
    }
    for (final c in childrenOf(id)) {
      if (c.isContainer) {
        total.addAll(valueOf(c.id));
      } else if (c.value case final v?) {
        total.add(v);
      }
    }
    return total;
  }

  /// Envanterin tamamının değeri: ana ekran, çekmece ve kayıplar (çöp sayılmaz).
  MoneyTotals get totalValue => valueOf(_allRoot);

  /// [valueOf] için üç kökü birlikte tutan sahte kimlik (yalnızca önbellek anahtarı).
  static const _allRoot = '__all__';

  ({List<Node> priced, List<Node> unpriced})? _valueRanking;

  /// Görünen eşyalar değerlerine göre: fiyatlılar büyükten küçüğe (önce envanterin ana
  /// biriminde olanlar; birimler karşılaştırılamaz), fiyatı olmayanlar elle dizilen sırayla.
  /// Değer sayfası ve döküm için; önbellekte, paylaşılır.
  ({List<Node> priced, List<Node> unpriced}) get valueRanking {
    final cached = _valueRanking;
    if (cached != null) return cached;
    final priced = <Node>[], unpriced = <Node>[];
    void walk(String id) {
      for (final c in childrenOf(id)) {
        if (c.isContainer) {
          walk(c.id);
        } else if (c.value != null) {
          priced.add(c);
        } else {
          unpriced.add(c);
        }
      }
    }

    for (final root in const [Roots.home, Roots.drawer, Roots.lost]) {
      walk(root);
    }
    final main = totalValue.mainCurrency;
    priced.sort((a, b) {
      final va = a.value!, vb = b.value!;
      if ((va.currency == main) != (vb.currency == main)) return va.currency == main ? -1 : 1;
      final c = vb.cents.compareTo(va.cents);
      return c != 0 ? c : compareNatural(nameOf(a), nameOf(b));
    });
    return _valueRanking = (priced: priced, unpriced: unpriced);
  }

  final Map<String, List<Node>> _displayCache = {};

  /// Destede/listede **gösterilecek** sıra. [childrenOf] kullanıcının elle
  /// dizdiği sıradır ve taşıma, sıraya koyma, sayım hep onunla çalışır; burası
  /// yalnızca görünümü ayardaki sıralamaya göre dizer. Klasörler yine önce
  /// (gruplama açıksa). Kayıp çekmecesi hep en son kaybolana göre.
  List<Node> displayChildrenOf(String parentId) {
    final sort = settings.deckSort;
    if (sort == DeckSort.manual || parentId == Roots.lost) return childrenOf(parentId);
    return _displayCache[parentId] ??= [...childrenOf(parentId)]..sort((a, b) {
        if (settings.groupKinds && a.isContainer != b.isContainer) return a.isContainer ? -1 : 1;
        int byName() => compareNatural(nameOf(a), nameOf(b));
        final c = switch (sort) {
          DeckSort.newest => b.createdAt.compareTo(a.createdAt),
          DeckSort.expiry => switch ((a.effectiveExpiry, b.effectiveExpiry)) {
              // Tarihi olanlar önce (en yakın üstte), olmayanlar ada göre sonda.
              (final x?, final y?) => x.compareTo(y),
              (_?, null) => -1,
              (null, _?) => 1,
              _ => 0,
            },
          _ => 0,
        };
        if (c != 0) return c;
        final n = byName();
        return n != 0 ? n : a.createdAt.compareTo(b.createdAt);
      });
  }

  int childCount(String id) => childrenOf(id).length;

  /// Çöpte olmayan bütün klasörler.
  Iterable<Node> get allContainers => _byId.values.where((n) => n.isContainer && isLive(n));

  /// Fotoğrafların ve ek dosyalarının bu cihazda kapladığı yer. Kayıtların
  /// (çöptekiler dahil) ve "Son silinenler"de bekleyenlerin diskteki dosyaları
  /// sayılır; aynı dosya iki kayıtta geçse de bir kez. Henüz inmemiş ekler yer
  /// tutmadığı için sayılmaz. Dosyalara tek tek bakıldığı için istenince hesaplanır.
  Future<StorageUsage> measureStorage() async {
    final photos = <String>{};
    final files = <String, (Node, Attachment)>{};
    final archived = <String>{};
    for (final n in _byId.values) {
      if (n.imagePath case final p? when p.isNotEmpty) photos.add(p);
      for (final a in n.attachments) {
        if (a.file case final f?) files.putIfAbsent(f, () => (n, a));
      }
    }
    for (final (n, _) in _purged.values) {
      if (n.imagePath case final p? when p.isNotEmpty) photos.add(p);
      for (final a in n.attachments) {
        if (a.file case final f? when !files.containsKey(f)) archived.add(f);
      }
    }
    Future<int?> sizeOf(String rel) async {
      final file = AppPaths.imageFile(rel);
      if (file == null) return null;
      try {
        return await file.length();
      } on FileSystemException {
        return null;
      }
    }

    // Hepsi birlikte sorulur: binlerce fotoğrafta tek tek beklemek uzun sürerdi.
    final wanted = [...photos, ...files.keys, ...archived];
    final sizes = await Future.wait(wanted.map(sizeOf));
    final size = {for (final (i, rel) in wanted.indexed) rel: ?sizes[i]};

    var photoCount = 0;
    var photoBytes = 0;
    for (final rel in photos) {
      final bytes = size[rel];
      if (bytes == null) continue;
      photoCount++;
      photoBytes += bytes;
    }
    var fileCount = 0;
    var fileBytes = 0;
    final sized = <StoredAttachment>[];
    for (final e in files.entries) {
      final bytes = size[e.key];
      if (bytes == null) continue;
      fileCount++;
      fileBytes += bytes;
      sized.add(StoredAttachment(node: e.value.$1, attachment: e.value.$2, bytes: bytes));
    }
    for (final rel in archived) {
      final bytes = size[rel];
      if (bytes == null) continue;
      fileCount++;
      fileBytes += bytes;
    }
    sized.sort((a, b) => b.bytes.compareTo(a.bytes));
    return StorageUsage(
      photoCount: photoCount,
      photoBytes: photoBytes,
      fileCount: fileCount,
      fileBytes: fileBytes,
      largest: sized.take(StorageUsage.listed).toList(),
    );
  }

  /// Görünen tüm kayıtlar: ana ekran, çekmece ve kayıplar, iç içe hepsi.
  int get visibleRecordCount =>
      descendantCount(Roots.home) + descendantCount(Roots.drawer) + descendantCount(Roots.lost);

  /// Klasörün içindeki toplam kayıt sayısı (tum alt ağaç).
  int descendantCount(String id) {
    var total = 0;
    for (final c in childrenOf(id)) {
      total += 1 + (c.isContainer ? descendantCount(c.id) : 0);
    }
    return total;
  }

  List<Node> get trash {
    final list = _byId.values.where((n) => n.isDeleted).toList()
      ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    return list;
  }

  /// Koke kadar atalar, köke en yakin olan basta.
  List<Node> ancestorsOf(String id) {
    final out = <Node>[];
    var cur = _byId[id]?.parentId;
    final seen = <String>{};
    while (cur != null && seen.add(cur)) {
      final n = _byId[cur];
      if (n == null) break;
      out.insert(0, n);
      cur = n.parentId;
    }
    return out;
  }

  /// "Ana ekran / Mutfak / Üst dolap" gibi okunabilir konum yolu.
  String pathLabel(String id) {
    final node = _byId[id];
    if (node == null) return strings.home;
    if (node.parentId == null && node.isLost) return strings.lostDrawer;
    return pathLabelForParent(node.parentId, inDrawer: node.inDrawer);
  }

  /// Kayıp eşyanın son bilinen yeri.
  String lastSeenLabel(Node node) => pathLabelForParent(node.lostFrom);

  /// Henuz kaydedilmemis taslaklar da yolunu gosterebilsin diye yol
  /// kimlikten değil üst kayittan hesaplanıyor.
  String pathLabelForParent(String? parentId, {bool inDrawer = false}) {
    if (parentId == null) return inDrawer ? strings.drawer : strings.home;
    final parts = <String>[];
    final seen = <String>{};
    var rootLabel = strings.home;
    String? cur = parentId;
    while (cur != null && seen.add(cur)) {
      final n = _byId[cur];
      if (n == null) break;
      parts.insert(0, nameOf(n));
      if (n.parentId == null) {
        rootLabel = n.isLost ? strings.lostDrawer : (n.inDrawer ? strings.drawer : strings.home);
        break;
      }
      cur = n.parentId;
    }
    return [rootLabel, ...parts].join(' / ');
  }

  /// Bir kaydın hangi seviyede durduğu: sanal kök ya da klasör kimliği.
  String bucketKey(Node n) =>
      n.parentId ?? (n.isLost ? Roots.lost : (n.inDrawer ? Roots.drawer : Roots.home));

  /// Adi boş bırakılan klasör için sıradaki sayı.
  String defaultContainerName(String bucket) => _nextDefaultName(bucket);

  Set<String> subtreeIds(String id) {
    final out = <String>{id};
    final stack = <String>[id];
    while (stack.isNotEmpty) {
      for (final n in _children[stack.removeLast()] ?? const <Node>[]) {
        if (out.add(n.id)) stack.add(n.id);
      }
    }
    return out;
  }

  /// [maybeAncestor] kendisi ya da atası mi? Dongusel tasimayi engeller.
  /// Alt ağacı çıkarmak yerine adaydan köke yürünür: sürüklerken her
  /// harekette sorulduğu için ucuz olmalı.
  bool isSelfOrDescendant(String maybeAncestor, String candidate) {
    final seen = <String>{};
    String? cur = candidate;
    while (cur != null && seen.add(cur)) {
      if (cur == maybeAncestor) return true;
      cur = _byId[cur]?.parentId;
    }
    return false;
  }

  /// Resmi olan canlı kayıt sayısı; görüntüyle aramanın anlamlı olup
  /// olmadığını söylüyor.
  int get imagedCount =>
      _byId.values.where((n) => !n.isDeleted && n.hasImage).length;

  /// Fotoğrafa yeterince benzeyen kayıtlar, en yakın önce. Eşik altındaki
  /// her şey elenir: yanlış yönlendirmektense boş dönmek daha iyi.
  Future<List<VisualMatch>> findByImage(File photo) async {
    final signatures = <String, ImageSignature>{};
    final backfilled = <Node>[];

    for (final node in _byId.values.toList()) {
      if (_closed) return const [];
      if (!node.hasImage || !isLive(node)) continue;
      var signature = ImageSignature.decode(node.imageSig);
      if (signature == null) {
        // Parmak izi olmadan (ya da eski biçimle) kaydedilmiş resimler.
        final file = AppPaths.imageFile(node.imagePath);
        if (file == null) continue;
        signature = await VisualIndex.signatureOf(file);
        if (signature == null || _closed) continue;
        // Parmak izi türetilmiş veri; düzenleme zamanını değiştirmemeli, yoksa
        // paylaşımda bu kayıt karşı tarafın gerçek düzenlemesini ezerdi.
        final updated = node.copyWith(
          imageSig: signature.encode(),
          updatedAt: node.updatedAt,
        );
        _byId[updated.id] = updated;
        _invalidate();
        backfilled.add(updated);
      }
      signatures[node.id] = signature;
    }

    if (backfilled.isNotEmpty && !_closed) {
      await _serial(() async {
        if (!_closed) {
          await AppDatabase.instance.upsertAll(backfilled);
          notifyListeners();
        }
      });
    }
    if (signatures.isEmpty || _closed) return const [];

    final scores = await VisualIndex.rank(photo, signatures);
    final matches = [
      for (final e in scores.entries)
        if (e.value >= kVisualMatchThreshold && _byId[e.key] != null)
          VisualMatch(node: _byId[e.key]!, score: e.value),
    ]..sort((a, b) => b.score.compareTo(a.score));
    return matches.take(5).toList();
  }

  /// Kapanırken yazılan arama dizini: öteki envanter açıkken bu envanterde
  /// arama ve QR ([InventoryLibrary.writeIndex]).
  List<IndexedRecord> searchIndex() => [for (final n in _byId.values) if (isLive(n)) indexRecord(n)];

  /// Dizindeki satırı; envanterler arası aktarma hedefin dizinine kendi kimliği ve yeriyle ekler.
  IndexedRecord indexRecord(Node n, {String? id, String? path}) => IndexedRecord(
        id: id ?? n.id,
        name: nameOf(n),
        container: n.isContainer,
        path: path ?? pathLabel(n.id),
        note: switch (n.note?.trim() ?? '') {
          final t when t.length > 300 => t.substring(0, 300),
          final t => t,
        },
        place: n.locationLabel?.trim() ?? '',
        quantity: n.quantity,
        barcode: n.barcode,
        attachments: [for (final a in n.attachments) a.name],
      );

  /// Alışveriş listesindeki eşyanın kısa nedeni ("2 kaldı", "tükendi"...).
  String shoppingNote(Node n, [DateTime? today]) => switch (shoppingReason(n, today)) {
        ShoppingReason.out => strings.outOfStockNote,
        ShoppingReason.low => strings.lowNote(n.quantity!),
        ShoppingReason.expired => strings.pastDateNote,
        null => '',
      };

  /// Kapanırken saklanan alışveriş listesi (bütün envanterlerin listesi için).
  List<SavedShop> savedShopping([DateTime? today]) => [
        for (final n in shoppingItems)
          SavedShop(
            id: n.id,
            name: nameOf(n),
            note: shoppingNote(n, today),
            kind: shoppingReason(n, today)?.name ?? 'wanted',
          ),
      ];

  /// Ad, konum adı, not ve ek adlarında arama. Harf farkı gözetilmez ([foldForSearch]:
  /// "cekic" Çekiç'i, "isitici" ISITICI'yı bulur); birden çok kelime
  /// yazıldıysa her biri kaydın bir yerinde geçmeli.
  /// Aramada bakılan metin (ad, gerisi), kaydın o haline bağlı: [Node] değişmez,
  /// değişen kayıt yeni bir nesnedir, eskisinin girdisi kendiliğinden düşer.
  static final Expando<(String, String)> _searchText = Expando();

  List<Node> search(String query) {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return const [];
    final whole = tokens.join(' ');
    final hits = <(Node, int, String)>[];
    for (final n in _byId.values) {
      if (n.isDeleted) continue;
      // Katlanmış metin kayıt başına bir kez hazırlanır (kayıt değişince yenisi):
      // her tuşta bütün adlar ve notlar yeniden katlanıyordu.
      final (name, rest) = _searchText[n] ??= (
        foldForSearch(n.trimmedName),
        // Eklerin adları da: "kılavuz" yazınca kılavuzu olan eşyalar çıksın.
        [
          foldForSearch(n.locationLabel ?? ''),
          foldForSearch(n.note ?? ''),
          for (final a in n.attachments) foldForSearch(a.name),
          // Barkodun rakamları yazılınca da bulunsun.
          if (n.barcode != null) foldForSearch(n.barcode!),
          // Seri numarası da (sigorta, servis: "SN 4B2..." yazınca cihaz çıksın).
          if (n.serial != null) foldForSearch(n.serial!),
        ].join('\n'),
      );
      if (!tokens.every((t) => name.contains(t) || rest.contains(t))) continue;
      if (!isLive(n)) continue;
      // Adı tam eşleşen, adı böyle başlayan, bütün kelimeleri adında geçen,
      // en son yalnızca notunda ya da konumunda geçen.
      final rank = name == whole
          ? 0
          : name.startsWith(whole)
              ? 1
              : tokens.every(name.contains)
                  ? 2
                  : 3;
      hits.add((n, rank, name));
    }
    hits.sort((a, b) {
      if (a.$2 != b.$2) return a.$2 - b.$2;
      // Aynı derecede klasörler önce, sonra alfabetik.
      if (a.$1.isContainer != b.$1.isContainer) return a.$1.isContainer ? -1 : 1;
      return a.$3.compareTo(b.$3);
    });
    return [for (final h in hits) h.$1];
  }

  /// Kayıt ne kendisi ne de üstündeki bir klasör çöpte. Silme yumuşak olduğu
  /// için çöpe atılan klasörün alt ağacı ayrıca işaretlenmez; yalnızca kaydın
  /// kendi işaretine bakan arama, çöpteki kutunun içindekileri de buluyordu.
  bool isLive(Node node) {
    if (node.isDeleted) return false;
    final parent = node.parentId;
    if (parent == null) return true;
    // Üstü çöpteyse ya da çöpteki bir klasörün altındaysa görünmez. Eskiden her
    // soruda köke kadar yüründü; arama ve tarih listeleri bunu her kayıt için
    // sorduğundan büyük envanterde her değişiklik gözle görülür bekletiyordu.
    return !(_byId[parent]?.isDeleted ?? false) && !_buried.contains(parent);
  }

  Set<String>? _buriedCache;

  /// Çöpteki bir kaydın altında kalan (kendisi işaretli olmasa da görünmeyen)
  /// kayıtların kimlikleri. Çöpte çoğu zaman az kayıt olduğu için ucuzdur;
  /// ağaç değişince düşer.
  Set<String> get _buried {
    final cached = _buriedCache;
    if (cached != null) return cached;
    final out = <String>{};
    for (final n in _byId.values) {
      if (!n.isDeleted || out.contains(n.id)) continue;
      final stack = <String>[n.id];
      while (stack.isNotEmpty) {
        for (final c in _children[stack.removeLast()] ?? const <Node>[]) {
          if (out.add(c.id)) stack.add(c.id);
        }
      }
    }
    return _buriedCache = out;
  }

  // ---------------------------------------------------------------- yazma

  double _nextSortIndex(String parentId) {
    final siblings = childrenOf(parentId);
    if (siblings.isEmpty) return 0;
    return siblings.last.sortIndex + 1;
  }

  /// Aynı seviyedeki kartlar bir bakışta ayırt edilsin diye paletten kardeşleri arasında en az kullanılan renk
  /// verilir, eşitlikte palet sırasıyla: önce hiç kullanılmamışlar, hepsi kullanılınca palet aynı sırayla yeniden
  /// döner (eskiden o noktadan sonra her yeni kart paletin ilk rengini alıyordu). Yeni kartın önünde duracak
  /// kardeşin rengi verilmez, destede üst üste binerler: kart sona eklenir; önünde klasörler ve eşyalar ayrı
  /// gruptaysa kendi türünün sonuncusu, ayrı değilse son kardeş durur.
  int _nextColor(String parentId, NodeKind kind) {
    final siblings = childrenOf(parentId);
    // Eski paletteki renkler bugünkü karşılıklarıyla sayılır.
    int colorOf(Node n) => canonicalCardColor(n.color).toARGB32();
    final counts = <int, int>{};
    for (final n in siblings) {
      counts.update(colorOf(n), (v) => v + 1, ifAbsent: () => 1);
    }
    final neighbors = <int>{if (siblings.isNotEmpty) colorOf(siblings.last)};
    for (final n in siblings.reversed) {
      if (n.kind == kind) {
        neighbors.add(colorOf(n));
        break;
      }
    }
    var best = kCardPalette.first.toARGB32();
    int? fewest;
    for (final c in kCardPalette) {
      final color = c.toARGB32();
      if (neighbors.contains(color)) continue;
      final uses = counts[color] ?? 0;
      if (fewest == null || uses < fewest) {
        best = color;
        fewest = uses;
      }
    }
    return best;
  }

  /// Klasörler için bir sonraki boş sayı: 1, 2, 3...
  String _nextDefaultName(String parentId) {
    final used = <int>{};
    for (final n in childrenOf(parentId)) {
      final v = int.tryParse(n.name.trim());
      if (v != null) used.add(v);
    }
    var i = 1;
    while (used.contains(i)) {
      i++;
    }
    return '$i';
  }

  /// Adı verilmeden kaydedilen eşyaya "Adsız N": envanterde boşalan en küçük
  /// numara (Adsız 2 silindiyse yenisi Adsız 2, sonrakiler 4, 5...). Hepsi
  /// "Adsız" olunca aramada ve listede birbirinden ayrılmıyordu.
  /// [taken]: henüz mağazada olmayan ama verilmiş adlar ([addAll]'da aynı turda numaralananlar).
  String nextUnnamed({String? except, Iterable<String> taken = const []}) {
    final word = strings.unnamed;
    final pattern = RegExp('^${RegExp.escape(word)} (\\d+)\$');
    final used = <int>{
      for (final n in _byId.values)
        if (!n.isContainer && n.id != except && isLive(n))
          if (pattern.firstMatch(n.trimmedName) case final m?) int.parse(m.group(1)!),
      for (final name in taken)
        if (pattern.firstMatch(name) case final m?) int.parse(m.group(1)!),
    };
    var i = 1;
    while (used.contains(i)) {
      i++;
    }
    return '$word $i';
  }

  /// Henuz diske yazilmamis taslak. Editorde tik'e basilinca [commit] edilir.
  Node draft({required String parentId, required NodeKind kind}) {
    final now = SyncClock.now();
    final inDrawer = parentId == Roots.drawer || parentId == Roots.lost;
    final realParent = Roots.isVirtual(parentId) ? null : parentId;
    return Node(
      id: _uuid.v4(),
      parentId: realParent,
      kind: kind,
      // Klasörün varsayılan adi var, eşyanın adi boş başlar.
      name: kind == NodeKind.container ? _nextDefaultName(parentId) : '',
      color: _nextColor(parentId, kind),
      sortIndex: _nextSortIndex(parentId),
      inDrawer: inDrawer,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> commit(Node node) async {
    final now = SyncClock.now();
    var saved = node.copyWith(updatedAt: now, updatedBy: authorId);
    // Adsız eşya numaralanır; eskiden adsız kalmış olan da ilk düzenlemede.
    if (!saved.isContainer && !saved.hasName && !saved.isDeleted) {
      saved = saved.copyWith(name: nextUnnamed(except: saved.id), updatedAt: now);
    }
    // "Ayşe'de" duran kaydı biri bir yere koydu: artık onda değil.
    final before = _byId[saved.id];
    if (saved.heldBy != null &&
        before != null &&
        (before.parentId != saved.parentId || before.inDrawer != saved.inDrawer)) {
      saved = saved.copyWith(clearHeld: true, updatedAt: saved.updatedAt);
    }
    // Kayıp eşyaya (ör. düzenleyiciden) bir yer verildiyse artık bulunmuştur.
    if (saved.isLost && (saved.parentId != null || saved.inDrawer)) {
      saved = saved.copyWith(clearLost: true, updatedAt: saved.updatedAt);
    }
    saved = stampChanges(before, saved, now);
    _byId[saved.id] = saved;
    if (before == null) _arrived.add(saved.id);
    _invalidate();
    await AppDatabase.instance.upsert(saved);
    // Üzerine yazılan bekleyen değişiklik artık geçersiz.
    if (_prunePending()) await _savePending();
    if (!saved.isDeleted) await _noteRecent([saved.id]);
    notifyListeners();
    _touched();
  }

  /// Birçok yeni kayıt tek yazımla (seri ekleme). Her biri [commit]'teki gibi damgalanır ve adsızsa
  /// numaralanır, ama veritabanına bir kez yazılır, "son dokunulanlar" bir kez, ekran bir kez yenilenir:
  /// 200 fotoğrafta tek tek [commit] 400 ayrı yazım ve 200 yeniden çizim demekti. Yalnızca yeni kayıtlar
  /// (var olanı değiştirmek [commit]'ten geçer); sıra numaralarını çağıran verir.
  Future<void> addAll(List<Node> nodes) async {
    if (nodes.isEmpty) return;
    final now = SyncClock.now();
    final names = <String>[];
    final added = <Node>[];
    for (final node in nodes) {
      assert(!_byId.containsKey(node.id), 'addAll yalnızca yeni kayıtlar içindir');
      var saved = node.copyWith(updatedAt: now, updatedBy: authorId);
      if (!saved.isContainer && !saved.hasName && !saved.isDeleted) {
        saved = saved.copyWith(name: nextUnnamed(taken: names), updatedAt: now);
        names.add(saved.name);
      }
      added.add(saved);
      _arrived.add(saved.id);
    }
    await _writeMany(added, recent: true);
  }

  Future<void> moveToTrash(String id) async {
    final n = _byId[id];
    if (n == null) return;
    // Alt ağaç işaretlenmez; atası çöpte oldugu için zaten görünmez olur.
    await commit(n.copyWith(deletedAt: SyncClock.now()));
  }

  /// Geri gelen "Adsız N", o arada aynı numarayı alan bir eşyayla çakışıyorsa
  /// yeni numara alır: numaralar ayırt etmek içindi.
  Node _unclash(Node n) {
    final word = RegExp.escape(strings.unnamed);
    if (n.isContainer || !RegExp('^$word \\d+\$').hasMatch(n.trimmedName)) return n;
    final taken = _byId.values.any(
      (o) => o.id != n.id && !o.isContainer && o.trimmedName == n.trimmedName && isLive(o),
    );
    return taken ? n.copyWith(name: nextUnnamed(except: n.id)) : n;
  }

  Future<void> restore(String id) async {
    final found = _byId[id];
    if (found == null) return;
    final n = _unclash(found);
    // Üstü görünmüyorsa (çöpte, çöpteki bir klasörün altında ya da silinmiş) kök seviyeye
    // değil çekmeceye dön. Yalnızca üstün kendi işaretine bakılırken, üstünün üstü çöpte olan
    // kayıt yerinde "geri geliyor", çöp listesinden çıkıp hiçbir yerde görünmüyordu.
    final parent = n.parentId == null ? null : _byId[n.parentId];
    final parentGone = n.parentId != null && (parent == null || !isLive(parent) || !parent.isContainer);
    if (parentGone && isPrivate(n.id)) await _markPrivate(n.id);
    await commit(n.copyWith(
      clearDeletedAt: true,
      parentId: parentGone ? null : n.parentId,
      clearParent: parentGone,
      inDrawer: parentGone ? true : n.inDrawer,
    ));
  }

  /// [now]: "Son silinenler"de bekletmeden, fotoğrafı ve ekleriyle hemen.
  Future<void> deleteForever(String id, {bool now = false}) => _purge(subtreeIds(id), archive: !now);

  /// Kalıcı silme tek yerde: bellekten düşür, mezar taşı bırak, tek yazım.
  /// Kayıt ve resmi [keepPurged] boyunca arşivde kalır ([restorePurged]); [archive] false ise
  /// arşive girmez, dosyaları hemen silinir. Mezar taşı her durumda kalır: yoksa başka cihazdaki
  /// eski kopya eşitlemede kaydı geri getirirdi.
  Future<void> _purge(Set<String> ids, {bool archive = true}) async {
    if (ids.isEmpty) return;
    final now = SyncClock.now();
    final gone = <Node>[];
    for (final i in ids) {
      if (_byId.remove(i) case final n?) gone.add(n);
      _tombstones[i] = now.millisecondsSinceEpoch;
    }
    _invalidate();
    await AppDatabase.instance.hardDelete(ids, at: now);
    if (archive) await _archivePurged(gone, now.millisecondsSinceEpoch);
    if (_prunePending()) await _savePending();
    // Bekleyen değişiklikler budandıktan sonra: onların tuttuğu eski sürüm dosyayı boşuna tutmasın.
    if (!archive) _discardUnused({for (final n in gone) ..._mediaOf(n)});
    // Kalıcı silinen kayıt sık kullanılanlarda kalmasın.
    final favorites = [for (final f in settings.favorites) if (!ids.contains(f)) f];
    if (favorites.length != settings.favorites.length) {
      await updateSettings(settings.copyWith(favorites: favorites));
    }
    notifyListeners();
    _touched();
  }

  // ---------------------------------------------------------------- kalıcı silinenler

  static const _purgedKey = 'purged_archive';

  /// Kalıcı silinenler bu kadar süre geri getirilebilir.
  static const keepPurged = Duration(days: 30);

  /// Kalıcı silinen kayıtlar (kimlik → kayıt, silinme anı ms): yanlışlıkla
  /// boşaltılan çöp ya da başkasının toplu silmesi geri gelebilsin. Resimleri de
  /// süre dolana kadar silinmez. Cihaza özel: eşitlenmez, yedeğe girmez.
  final Map<String, (Node, int)> _purged = {};

  Future<void> _loadPurged() async {
    _purged.clear();
    final text = await AppDatabase.instance.readMeta(_purgedKey);
    if (text == null || text.isEmpty) return;
    try {
      for (final e in jsonDecode(text) as List) {
        final at = e['at'];
        final node = Node.fromMap(Map<String, Object?>.from(e['node'] as Map));
        if (at is int && !_byId.containsKey(node.id)) _purged[node.id] = (node, at);
      }
    } on Object {
      // Bozuk arşiv: yalnızca geri getirme imkânı gider, envanter etkilenmez.
      _purged.clear();
    }
    if (_expirePurged(DateTime.now().millisecondsSinceEpoch)) await _savePurged();
  }

  Future<void> _savePurged() => AppDatabase.instance.writeMeta(
        _purgedKey,
        jsonEncode([
          for (final (node, at) in _purged.values) {'at': at, 'node': node.toMap()},
        ]),
      );

  /// Süresi dolanları düşürür; resimleri artık kimse kullanmıyorsa silinir.
  bool _expirePurged(int now) {
    final limit = now - keepPurged.inMilliseconds;
    final old = [for (final e in _purged.entries) if (e.value.$2 < limit) e.key];
    if (old.isEmpty) return false;
    final images = {for (final id in old) ..._mediaOf(_purged.remove(id)?.$1)};
    _discardUnused(images);
    return true;
  }

  Future<void> _archivePurged(Iterable<Node> nodes, int at) async {
    var changed = _expirePurged(at);
    for (final n in nodes) {
      _purged[n.id] = (n, at);
      changed = true;
    }
    if (changed) await _savePurged();
  }

  /// Geri getirilebilecek kalıcı silinenler: en üsttekiler (klasörle birlikte
  /// silinen içindekiler onunla gelir), en yeni önce.
  List<PurgedRecord> get recentlyPurged {
    final inside = <String, int>{};
    for (final (n, at) in _purged.values) {
      // Aynı anda silinen bir atanın altındaysa onunla sayılır.
      final seen = <String>{};
      var up = n.parentId;
      while (up != null && seen.add(up)) {
        final parent = _purged[up];
        if (parent == null || parent.$2 != at) break;
        inside[up] = (inside[up] ?? 0) + 1;
        up = parent.$1.parentId;
      }
    }
    bool top((Node, int) e) {
      final parent = _purged[e.$1.parentId];
      return parent == null || parent.$2 != e.$2;
    }

    return [
      for (final e in _purged.values)
        if (top(e)) PurgedRecord(node: e.$1, at: DateTime.fromMillisecondsSinceEpoch(e.$2), inside: inside[e.$1.id] ?? 0),
    ]..sort((a, b) => b.at.compareTo(a.at));
  }

  /// "Son silinenler"den beklemeden tamamen siler: [id] verilirse o kayıt ve onunla birlikte silinen
  /// içindekiler, verilmezse hepsi. Geri getirilemez; fotoğrafları ve ek dosyaları (başka kayıt
  /// kullanmıyorsa) hemen silinir, yer açılır. Arşiv cihaza özel: başka cihazların arşivine dokunmaz,
  /// silme izleri de durur.
  Future<void> discardPurged([String? id]) async {
    final ids = <String>{};
    if (id == null) {
      ids.addAll(_purged.keys);
    } else {
      final root = _purged[id];
      if (root == null) return;
      ids.add(id);
      var grew = true;
      while (grew) {
        grew = false;
        for (final (n, at) in _purged.values) {
          if (at == root.$2 && !ids.contains(n.id) && ids.contains(n.parentId)) grew = ids.add(n.id);
        }
      }
    }
    if (ids.isEmpty) return;
    final media = {for (final i in ids) ..._mediaOf(_purged.remove(i)?.$1)};
    // Önce arşiv yazılır: dosya silinip arşiv yazılmadan kesilirse kayıt resimsiz geri getirilebilirdi.
    await _savePurged();
    _discardUnused(media);
    notifyListeners();
  }

  /// Kalıcı silineni (ve onunla silinen içindekileri) geri getirir; çöpten
  /// silinmiş olsa da çöpe değil yerine döner. Bütün alanları şimdiye
  /// damgalanır: silme izinden yeni olduğu için başka cihazlarda da geri gelir.
  /// Yeri artık yoksa çekmeceye.
  Future<void> restorePurged(String id) async {
    final root = _purged[id];
    if (root == null) return;
    final ids = <String>{id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final (n, at) in _purged.values) {
        if (at == root.$2 && !ids.contains(n.id) && ids.contains(n.parentId)) grew = ids.add(n.id);
      }
    }
    final now = SyncClock.now();
    final parent = _byId[root.$1.parentId];
    final homeless = root.$1.parentId != null && (parent == null || !isLive(parent) || !parent.isContainer);
    if (homeless && _privateAbove(root.$1.parentId)) await _markPrivate(id);
    Node back(Node n) => n.id != id
        ? n
        : homeless
            ? _unclash(n).copyWith(clearDeletedAt: true, clearParent: true, inDrawer: true)
            : _unclash(n).copyWith(clearDeletedAt: true);
    final restored = [
      for (final i in ids) stampChanges(null, back(_purged[i]!.$1).copyWith(updatedAt: now, updatedBy: authorId), now),
    ];
    for (final n in restored) {
      _byId[n.id] = n;
      _tombstones.remove(n.id);
      _purged.remove(n.id);
    }
    _arrived.addAll(ids);
    _invalidate();
    await AppDatabase.instance.applySync(
      upserts: restored,
      removals: const [],
      tombstones: const {},
      clearedTombstones: ids,
    );
    await _savePurged();
    await _noteRecent([id]);
    notifyListeners();
    _touched();
  }

  // ---------------------------------------------------------------- ortak kullanım

  final ValueNotifier<int> _localRevision = ValueNotifier(0);

  @override
  ValueListenable<int> get localRevision => _localRevision;

  /// Bu cihazdaki her kalıcı düzenlemeden sonra; ortak kullanım bununla
  /// değişikliği karşıya gönderir.
  void _touched() {
    _reconcileHeld();
    _localRevision.value++;
  }

  /// Karşıya gidecek, çöpte olmayan kayıt sayısı ("sendeki N kayıt da
  /// eklenecek"); yalnızca bende tutulanlar sayılmaz.
  /// Çöpte olmayan bütün kayıtlar (özel olanlar dahil): envanter listesinde,
  /// envanter kapalıyken gösterilir.
  /// Görünen kayıtlar (sol menüdeki toplamla aynı): çöpteki klasörün içindekiler sayılmaz.
  int get totalRecordCount => _byId.values.where(isLive).length;

  bool _closed = false;
  bool get isClosed => _closed;

  /// Envanter kapanırken çağrılır; arka plan tarama/yazımları durur.
  void close() {
    _closed = true;
  }

  /// Kuyruktaki birleştirmeler bitene kadar bekler: envanter kapanmadan önce,
  /// veritabanı yazım ortasında kapanmasın.
  Future<void> settle() => _serial(() async {});

  @override
  int get liveRecordCount => _byId.values.where((n) => !n.isDeleted && !isPrivate(n.id)).length;

  String? _stampCache;

  /// Eşitlenecek her şeyin küçük bir özeti. Karşı cihaz duyurusunda bunu
  /// taşır: damga son eşitlemedekiyle aynıysa konuşacak bir şey yoktur ve
  /// envanter boşuna gidip gelmez. Kayıt sayısı, kayıtların kimlik+zaman
  /// karmalarının XOR'u ve silme izleri girer; herhangi biri değişince
  /// damga da değişir. Sırasız hesaplandığı için iki taraf aynı sonucu
  /// vermek zorunda değil: her cihaz yalnızca kendi damgasını üretir.
  @override
  String get stateStamp => _stampCache ??= stateStampOf(_outgoing().values, _tombstones);

  /// Karşıya gidecek durum: yalnızca bende tutulanlar ve içleri girmez; daha
  /// önce ortak olup özel alana alınanların yerine son bildirilen sürümleri
  /// ("Ayşe'de") gider.
  @override
  ({Map<String, Node> nodes, Map<String, int> tombstones}) snapshot() =>
      (nodes: _outgoing(), tombstones: Map.of(_tombstones));

  Map<String, Node> _outgoing() => {
        for (final e in _byId.entries)
          if (!isPrivate(e.key))
            e.key: e.value
          else
            e.key: ?_heldOut[e.key],
      };

  /// Yedek dosyası için her şey, yalnızca bende tutulanlar dahil.
  ({Map<String, Node> nodes, Map<String, int> tombstones}) fullSnapshot() =>
      (nodes: Map.of(_byId), tombstones: Map.of(_tombstones));

  // ---------------------------------------------------------------- yalnızca bende

  Set<String>? _privateCache;

  /// Yalnızca bende tutulan kayıtlar: işaretliler ve içlerindeki her şey.
  /// Kart her karede sorduğu için önbellekli; ağaç ya da ayar değişince düşer.
  Set<String> get _privateSet => _privateCache ??= {
        for (final id in settings.privateIds) ...(_byId.containsKey(id) ? subtreeIds(id) : {id}),
      };

  /// Kayıt başka cihazlara gönderilmez (kendisi ya da bir üst klasörü işaretli).
  bool isPrivate(String? id) => id != null && _privateSet.contains(id);

  /// İşaret kaydın kendisinde mi (üst klasörden gelmiyor): yalnızca o zaman
  /// kaldırılabilir.
  bool isPrivateRoot(String id) => settings.privateIds.contains(id);

  /// "Yalnızca bende tut" ya da yeniden ortak yap. Özel yapmak daha önce
  /// gönderilmiş kopyayı diğer cihazlardan silmez (onların kaydı olmuş olabilir);
  /// yalnızca bundan sonrası gitmez. Ortak yapınca kayıt ve içi yeniden gider.
  Future<void> setPrivate(String id, bool private) async {
    final ids = [...settings.privateIds];
    if (private) {
      if (ids.contains(id)) return;
      // İçerideki ayrı işaretler gereksizleşir; klasörün işareti hepsini kapsar.
      final inside = _byId.containsKey(id) ? subtreeIds(id) : {id};
      ids
        ..removeWhere(inside.contains)
        ..add(id);
    } else if (!ids.remove(id)) {
      return;
    }
    await updateSettings(settings.copyWith(privateIds: ids));
    if (private) {
      // Özel kayda karşıdan gelmiş, onay bekleyen değişiklik artık konu dışı.
      final before = _pending.length;
      _pending.removeWhere((key, _) => isPrivate(key));
      if (_pending.length != before) {
        await _savePending();
        notifyListeners();
      }
    }
    // Ortak kayıt özel alana girdiyse son haberi, yeniden ortaksa kendisi gitsin.
    _touched();
  }

  /// Özelliğini üst klasöründen alan kayıt o klasörün dışına (çekmeceye) geri getirilirken
  /// işaret kaydın kendisine konur: yoksa artık hiçbir özel klasörün altında olmadığı için
  /// bütün içeriğiyle karşıya giderdi. Kayıt yazılmadan önce çağrılır (bir an bile gitmesin).
  Future<void> _markPrivate(String id) async {
    if (isPrivateRoot(id)) return;
    await updateSettings(settings.copyWith(privateIds: [...settings.privateIds, id]));
  }

  /// Kalıcı silinmiş bir kaydın üstlerinden biri özel mi. Duran kayıtta [isPrivate] yeter;
  /// üstü de kalıcı silinmişse zincir arşivden ([_purged]) izlenir.
  bool _privateAbove(String? id) {
    final seen = <String>{};
    while (id != null && seen.add(id)) {
      if (isPrivate(id)) return true;
      if (_byId.containsKey(id)) return false;
      id = _purged[id]?.$1.parentId;
    }
    return false;
  }

  /// Özel alana alınmış ortak kayıtların karşıya son bildirilen sürümü:
  /// çekmecede, "bende" işaretli. Diğerleri eşyanın nerede olduğunu bilsin,
  /// kendi envanterlerinde eski yerinde aramasınlar. Uygulama kapanıp açılsa
  /// da (karşıdaki cihaz o an ağda değilse) gitmeye devam etsin diye saklanır.
  final Map<String, Node> _heldOut = {};

  static const _heldKey = 'held_out';

  /// Eşitlemenin en son ne zaman olduğu (ortak kullanım verir). Bundan önce
  /// var olan bir kayıt karşıya gitmiş sayılır; sonra oluşturulup hemen özel
  /// alana konan kayıt için kimseye haber verilmez.
  DateTime? Function()? lastSyncAt;

  /// Son bakışta özel olanlar. Yalnızca özel olduğu anda son eşitlemeden önce
  /// var olan kayıt ortak sayılır: baştan beri özel olan bir klasör de son
  /// eşitlemeden eski olabilir ama hiç gönderilmemiştir.
  Set<String> _knownPrivate = {};

  /// Mağazaya o anda giren kayıtlar: yeni kaydedilen eşya, içe aktarılan yedek, Son
  /// silinenler'den dönenler. Özel bir yere girdilerse "ortakken özel oldu" sayılmazlar:
  /// karşıda hiç olmadılar. Yalnızca oluşturulma anına bakılırken, özel klasöre kaydedilen
  /// yeni eşya (düzenleyici açıkken bir eşitleme bittiyse) ve yedekten gelen özel kayıtlar
  /// "bende" haberiyle, bütün içerikleriyle karşıya gidiyordu. [_reconcileHeld] gelenleri düşer.
  final Set<String> _arrived = {};

  Future<void> _loadHeld() async {
    _heldOut.clear();
    final raw = await AppDatabase.instance.readMeta(_heldKey);
    if (raw == null || raw.isEmpty) return;
    try {
      for (final m in jsonDecode(raw) as List) {
        final n = Node.fromMap(Map<String, Object?>.from(m as Map));
        _heldOut[n.id] = n;
      }
    } on Object {
      _heldOut.clear(); // bozuksa yeniden hesaplanır
    }
  }

  /// Özel alana giren ortak kayıtlar için son sürümü hazırlar, yeniden ortak
  /// olan ya da silinenlerinkini bırakır. Her yerel yazımdan sonra çalışır:
  /// taşıma, işaretleme, düzenleme hangi yoldan olursa olsun.
  void _reconcileHeld() {
    final private = _privateSet;
    // Diske milisaniyeyle yazılır; bellekteki sürüm açılıştakiyle aynı kalsın.
    final now = DateTime.fromMillisecondsSinceEpoch(SyncClock.now().millisecondsSinceEpoch);
    var changed = false;
    for (final id in _heldOut.keys.toList()) {
      final n = _byId[id];
      if (n != null && private.contains(id)) continue;
      _heldOut.remove(id);
      changed = true;
      // Yeniden ortak: gerçek sürüm son bildirilenden yeni olmalı, yoksa
      // karşıda kayıt "Ayşe'de" kalırdı.
      if (n != null) {
        final fresh = bumpFields(n, const [NodeField.placement], now, by: authorId);
        _byId[id] = fresh;
        unawaited(AppDatabase.instance.upsert(fresh));
      }
    }
    final last = lastSyncAt?.call();
    final me = authorId;
    final fresh = private.difference(_knownPrivate).difference(_arrived);
    // Yolda olan (içe aktarması süren) kimlikler bir sonraki bakışa kalır.
    _arrived.removeWhere(_byId.containsKey);
    _knownPrivate = {...private};
    if (last != null && me != null && fresh.isNotEmpty) {
      // Şimdi özel olan ve karşının elinde olan (son eşitlemeden önce var olan).
      final shared = {
        for (final id in fresh)
          if (_byId[id] case final n? when !n.isDeleted && n.createdAt.isBefore(last)) id,
      };
      for (final id in shared) {
        if (_heldOut.containsKey(id)) continue;
        final n = _byId[id]!;
        // Klasörü de karşıya "bende" diye gidiyorsa içindekiler onun içinde
        // kalır; yoksa çekmeceye.
        final parent = n.parentId;
        final keepParent = parent != null && (shared.contains(parent) || _heldOut.containsKey(parent));
        _heldOut[id] = stampChanges(
          n,
          n.copyWith(
            parentId: keepParent ? n.parentId : null,
            clearParent: !keepParent,
            inDrawer: !keepParent,
            clearLost: true,
            heldBy: me,
            updatedAt: now,
            updatedBy: me,
          ),
          now,
        );
        changed = true;
      }
    }
    if (!changed) return;
    _invalidate();
    unawaited(AppDatabase.instance.writeMeta(
      _heldKey,
      jsonEncode([for (final n in _heldOut.values) n.toMap()]),
    ));
  }

  /// Karşıdan gelende bende özel olan kayıtlar yok sayılır: daha önce
  /// gönderilmiş eski kopyası karşıda düzenlense, taşınsa ya da silinse de
  /// buradaki özel kayda dokunulmaz.
  ({Map<String, Node> nodes, Map<String, int> tombstones}) _withoutPrivate(
    Map<String, Node> nodes,
    Map<String, int> tombstones,
  ) =>
      (
        nodes: {
          for (final e in nodes.entries)
            if (!isPrivate(e.key)) e.key: e.value,
        },
        tombstones: {
          for (final e in tombstones.entries)
            if (!isPrivate(e.key)) e.key: e.value,
        },
      );

  /// Yedek dosyasını birleştirir. Ağdan gelenden farkı: dosya bu cihazın
  /// (ya da kullanıcının) kendisi; özel işaretleri önce alınır, özel kayıtlar
  /// süzülmez.
  Future<MergeStats> importBackup({
    required Map<String, Node> nodes,
    required Map<String, int> tombstones,
    Iterable<String> privateIds = const [],
  }) async {
    final extra = [for (final id in privateIds) if (!settings.privateIds.contains(id)) id];
    if (extra.isNotEmpty) {
      await updateSettings(settings.copyWith(privateIds: [...settings.privateIds, ...extra]));
    }
    return _serial(() async {
      // Yedekten gelen yeni kayıtlar özelse baştan özeldir (bkz. [_arrived]).
      final fresh = [for (final id in nodes.keys) if (!_byId.containsKey(id)) id];
      _arrived.addAll(fresh);
      try {
        // Kullanıcının kendi dosyası: içindeki silmeler sorulmaz.
        return await _mergeNow(nodes, tombstones, guard: false);
      } finally {
        // Bilinen özeller hemen güncellensin; hiç gelmeyen kimlik de beklemesin.
        _reconcileHeld();
        _arrived.removeAll(fresh);
      }
    });
  }

  /// Karşı cihazın durumunu birleştirir. Resimler sonra [saveImage] ile
  /// gelir; o arada kart yalnızca rengini gösterir.
  /// Birleştirmeler sırayla: iki cihaz aynı anda veri iterse, ikisi de aynı
  /// eski durumdan hesap yapıp birbirinin yeni kaydını ezebilirdi.
  Future<void> _mergeQueue = Future.value();

  Future<T> _serial<T>(Future<T> Function() job) {
    final run = _mergeQueue.then((_) => job());
    _mergeQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  @override
  Future<MergeStats> mergeRemote({
    required Map<String, Node> nodes,
    required Map<String, int> tombstones,
    bool review = false,
    String? from,
  }) =>
      _serial(() {
        final shared = _withoutPrivate(nodes, tombstones);
        return review
            ? _stage(shared.nodes, shared.tombstones, from)
            : _mergeNow(shared.nodes, shared.tombstones, from: from);
      });

  /// Toplu çöpe atmanın eşiği (çöpe gidenler içindekileriyle sayılır).
  static const bulkTrash = 5;

  /// Başkasından gelen, otomatik kabulde de (yetkiliden gelse de) onay bekleyen
  /// değişiklikler: bizde görünen bir kaydın kalıcı silinmesi ve tek eşitlemede
  /// [bulkTrash] ya da daha çok kaydın çöpe gitmesi. Biri yanlışlıkla çöpü
  /// boşaltınca ya da dolu bir klasörü atınca herkesin telefonundan anında
  /// gitmesin. Zaten çöpte olanın kalıcı silinmesi sorulmaz (arşive girer).
  Set<String> _riskyIncoming(Map<String, Node> nodes, Map<String, int> tombstones) {
    final risky = <String>{};
    tombstones.forEach((id, at) {
      final local = _byId[id];
      if (local == null || !isLive(local)) return;
      // Silindikten sonra düzenlenmiş: birleşmede zaten kalır.
      if (local.updatedAt.millisecondsSinceEpoch > at) return;
      if (nodes[id] case final inc? when inc.updatedAt.millisecondsSinceEpoch > at) return;
      risky.add(id);
    });
    final trashed = <String>[];
    var weight = 0;
    for (final inc in nodes.values) {
      final local = _byId[inc.id];
      if (local == null || !inc.isDeleted || risky.contains(inc.id) || !isLive(local)) continue;
      if (!mergeNode(local, inc).isDeleted) continue;
      trashed.add(inc.id);
      weight += subtreeIds(inc.id).where((i) => _byId[i]?.isDeleted == false).length;
    }
    if (weight >= bulkTrash) risky.addAll(trashed);
    return risky;
  }

  Future<MergeStats> _mergeNow(
    Map<String, Node> nodes,
    Map<String, int> tombstones, {
    String? from,
    bool guard = true,
  }) async {
    final risky = guard ? _riskyIncoming(nodes, tombstones) : const <String>{};
    var held = 0;
    if (risky.isNotEmpty) {
      held = (await _stage(
        {for (final id in risky) id: ?nodes[id]},
        {for (final id in risky) id: ?tombstones[id]},
        from,
      ))
          .pending;
      nodes = {...nodes}..removeWhere((id, _) => risky.contains(id));
      tombstones = {...tombstones}..removeWhere((id, _) => risky.contains(id));
    }
    final result = mergeInventories(
      local: Map.of(_byId),
      localTombstones: Map.of(_tombstones),
      incoming: nodes,
      incomingTombstones: tombstones,
      now: SyncClock.now(),
      author: authorId,
    );
    await _applyMerge(result);
    if (_prunePending()) await _savePending();
    if (result.changesAnything) notifyListeners();
    // Çekmeceye alınanlar bu cihazda yapılmış bir düzeltme; karşıya da gitsin.
    if (result.stats.relocated > 0) _touched();
    return result.stats..pending = held;
  }

  final StreamController<LostEvent> _lostEvents = StreamController.broadcast();

  /// Başka cihazlardan gelen kayıp bildirimleri ve bulunma haberleri.
  Stream<LostEvent> get lostEvents => _lostEvents.stream;

  Future<void> _applyMerge(MergeResult result) async {
    if (!result.changesAnything) return;
    final lostBefore = {for (final n in result.upserts) n.id: _byId[n.id]?.isLost};

    // Artık hiçbir kayda ait olmayacak eski resimler.
    final orphanedImages = <String>{
      for (final id in result.removals) ..._mediaOf(_byId[id]),
      for (final n in result.upserts) ..._mediaOf(_byId[n.id]).difference(_mediaOf(n)),
    };

    await AppDatabase.instance.applySync(
      upserts: result.upserts,
      removals: result.removals,
      tombstones: result.tombstones,
      clearedTombstones: result.clearedTombstones,
    );
    // Başkasının kalıcı sildiği de bu cihazda 30 gün geri getirilebilir.
    final removed = [for (final id in result.removals) ?_byId[id]];
    for (final id in result.removals) {
      _byId.remove(id);
    }
    if (removed.isNotEmpty) {
      await _archivePurged(removed, DateTime.now().millisecondsSinceEpoch);
    }
    for (final n in result.upserts) {
      _byId[n.id] = n;
    }
    _invalidate();
    _tombstones
      ..clear()
      ..addAll(result.tombstones);
    _discardUnused(orphanedImages);

    for (final n in result.upserts) {
      final was = lostBefore[n.id];
      if (was == null || was == n.isLost || n.updatedBy == authorId || n.isDeleted) continue;
      _lostEvents.add(LostEvent(node: n, found: !n.isLost, by: n.updatedBy));
    }
  }

  /// Karttan kaldırılan resmi siler — başka bir kayıt ya da onay bekleyen bir
  /// değişiklik hâlâ kullanıyorsa dosyaya dokunulmaz.
  void discardImage(String? rel) {
    if (rel == null || rel.isEmpty) return;
    _discardUnused({rel});
  }

  /// Kayıttan çıkarılan (ya da kaydedilmeden vazgeçilen) eklerin dosyaları;
  /// resimle aynı kural: hâlâ kullanan varsa durur.
  void discardFiles(Iterable<String?> rels) => _discardUnused({
        for (final rel in rels)
          if (rel != null && rel.isNotEmpty) rel,
      });

  /// Kaydın diskteki dosyaları: kart resmi ve eklerin dosyaları.
  static Set<String> _mediaOf(Node? n) => n == null
      ? const {}
      : {
          if (n.imagePath case final img? when img.isNotEmpty) img,
          for (final a in n.attachments) ?a.file,
        };

  /// Hiçbir kaydın ve bekleyen değişikliğin kullanmadığı dosyaları (resim, ek) siler.
  void _discardUnused(Set<String> candidates) {
    if (candidates.isEmpty) return;
    final stillUsed = {
      for (final n in _byId.values) ..._mediaOf(n),
      for (final c in _pending.values) ..._mediaOf(c.incoming),
      for (final (n, _) in _purged.values) ..._mediaOf(n),
    };
    for (final rel in candidates) {
      if (!stillUsed.contains(rel)) ImageService.discard(rel);
    }
  }

  // ---------------------------------------------------------------- bekleyen değişiklikler

  /// Bu cihazın ortak kullanım kimliği; düzenlemeler bununla imzalanır ki
  /// karşıda "kim yaptı" görünsün.
  String? authorId;

  /// Cihaz genel ana kullanıcı mı (ortak kullanım bilir).
  bool Function(String deviceId)? isAdmin;

  /// Bu cihazın "değişiklikleri sormadan gelsin" dediği üye mi.
  bool Function(String deviceId)? isTrusted;

  /// Adet ve alışveriş listesi değişiklikleri sormadan gelsin mi.
  bool Function()? acceptsSmall;

  /// Onaylı modda da sormadan gelen küçük değişikliklerin grupları.
  static const _smallFields = {NodeField.quantity, NodeField.wanted};

  /// Yalnızca adedi (paketleriyle) ya da alışveriş listesindeki yeri değişen,
  /// bizde zaten olan kayıt.
  bool _isSmall(PendingChange change) {
    final local = _byId[change.nodeId];
    final inc = change.incoming;
    if (local == null || inc == null || !(acceptsSmall?.call() ?? false)) return false;
    final diff = differingFields(local, mergeNode(local, inc));
    return diff.isNotEmpty && diff.every(_smallFields.contains);
  }

  bool _isTrusted(PendingChange change) {
    final author = change.author;
    return author != null && author != authorId && (isTrusted?.call(author) ?? false);
  }

  /// Kaydın kendisinin ve üstündeki klasörlerin sorumluları.
  Set<String> managersOf(String? nodeId) {
    final out = <String>{};
    final seen = <String>{};
    var cur = nodeId;
    while (cur != null && seen.add(cur)) {
      final n = _byId[cur];
      if (n == null) break;
      out.addAll(n.managers);
      cur = n.parentId;
    }
    return out;
  }

  /// Bu değişikliği yapan, onu onaysız uygulatacak yetkide mi? Ana kullanıcı
  /// her yerde; sorumlu, kaydın bizdeki yerinde (yeni kayıtta konacağı yerde).
  bool _isAuthority(PendingChange change) {
    final author = change.author;
    if (author == null || author == authorId) return false;
    if (isAdmin?.call(author) ?? false) return true;
    final local = _byId[change.nodeId];
    if (local == null) {
      return managersOf(change.incoming?.parentId).contains(author);
    }
    if (!managersOf(local.id).contains(author)) return false;
    final targetParent = change.incoming?.parentId;
    if (targetParent != null && targetParent != local.parentId) {
      if (!managersOf(targetParent).contains(author)) return false;
    }
    return true;
  }

  final StreamController<AuthorityEvent> _authorityEvents = StreamController.broadcast();

  /// Yetkili birinin onaysız uygulanan değişiklikleri (bildirim için).
  Stream<AuthorityEvent> get authorityEvents => _authorityEvents.stream;

  static const _pendingKey = 'pending_changes';

  /// Karşıdan gelmiş, onay bekleyen sürümler (kayıt kimliği → değişiklik).
  final Map<String, PendingChange> _pending = {};

  List<ChangeGroup>? _groupsCache;
  Set<String>? _marksCache;

  @override
  void notifyListeners() {
    _groupsCache = null;
    _marksCache = null;
    _invalidate();
    super.notifyListeners();
  }

  /// Listede satır satır gösterilecek bekleyen değişiklikler, en yeni önce.
  List<ChangeGroup> get pendingGroups => _groupsCache ??= groupChanges(_pending, _byId);

  int get pendingCount => pendingGroups.length;

  PendingChange? pendingFor(String id) => _pending[id];

  List<PendingChange> get pendingChanges => List.unmodifiable(_pending.values);

  /// Kartında "bekleyen değişiklik" işareti olacak kayıtlar: değişen kayıt
  /// ve (içine bir şey eklenen, içinden bir şey çıkan) klasörler.
  bool hasPendingMark(String id) => (_marksCache ??= _computeMarks()).contains(id);

  Set<String> _computeMarks() {
    final marks = <String>{};
    for (final c in _pending.values) {
      marks.add(c.nodeId);
      for (final parent in {candidateOf(c, _byId[c.nodeId])?.parentId, _byId[c.nodeId]?.parentId}) {
        if (parent == null) continue;
        marks.add(parent);
        for (final a in ancestorsOf(parent)) {
          marks.add(a.id);
        }
      }
    }
    return marks;
  }

  Future<MergeStats> _stage(
    Map<String, Node> nodes,
    Map<String, int> tombstones,
    String? from,
  ) async {
    final now = SyncClock.now();
    final stats = MergeStats();
    final risky = _riskyIncoming(nodes, tombstones);

    // Görünür farkı olmayanlar (yalnızca zamanı değişmiş) doğrudan alınır.
    final quiet = quietIncoming(local: _byId, incoming: nodes);
    if (quiet.isNotEmpty) {
      await _applyMerge(mergeInventories(
        local: Map.of(_byId),
        localTombstones: Map.of(_tombstones),
        incoming: quiet,
        incomingTombstones: const {},
        now: now,
        author: authorId,
      ));
    }

    final allStaged = stageIncoming(
      local: _byId,
      localTombstones: _tombstones,
      incoming: nodes,
      incomingTombstones: tombstones,
      now: now,
    );

    // Yetkili ya da güvenilen birinin değişiklikleri ve küçük değişiklikler
    // (adet, alışveriş listesi) onay beklemez; kalıcı ya da toplu silme hariç.
    final small = <String>{};
    final authoritative = [
      for (final c in allStaged)
        if (!risky.contains(c.nodeId))
          if (c.withVia(from).attributedTo(authorId) case final a
              when _isAuthority(a) || _isTrusted(a) || (_isSmall(a) && small.add(a.nodeId)))
            a,
    ];
    if (authoritative.isNotEmpty) {
      await _applyMerge(mergeInventories(
        local: Map.of(_byId),
        localTombstones: Map.of(_tombstones),
        incoming: {for (final c in authoritative) c.nodeId: ?c.incoming},
        incomingTombstones: {
          for (final c in authoritative)
            if (c.isDeletion) c.nodeId: c.purgedAt!,
        },
        now: now,
        author: authorId,
      ));
      // Küçük değişiklikler sessizce gelir; ötekiler kimin yaptığıyla duyurulur.
      final byAuthor = <String, int>{};
      for (final c in authoritative) {
        if (small.contains(c.nodeId) || c.author == null) continue;
        byAuthor[c.author!] = (byAuthor[c.author!] ?? 0) + 1;
      }
      byAuthor.forEach((author, count) => _authorityEvents.add(AuthorityEvent(author: author, count: count)));
    }
    final applied = {for (final c in authoritative) c.nodeId};
    final staged = [for (final c in allStaged) if (!applied.contains(c.nodeId)) c];
    var changed = authoritative.isNotEmpty;
    final replacedImages = <String>{};
    for (final raw in staged) {
      final change = raw.withVia(from).attributedTo(authorId);
      final prev = _pending[change.nodeId];
      // Aynı kayda ikinci bir değişiklik: ikisi alan alan birleşip tek satır
      // olur (Ayşe adı, Ali adedi değiştirdi; yenisi eskisini silmesin).
      if (prev?.incoming case final old? when change.incoming != null) {
        final combined = mergeNode(old, change.incoming!);
        if (sameVersion(combined, old)) continue;
        replacedImages.addAll(_mediaOf(old).difference(_mediaOf(combined)));
        _pending[change.nodeId] = PendingChange(
          nodeId: change.nodeId,
          incoming: combined,
          purgedAt: null,
          receivedAt: change.receivedAt,
          via: change.via,
        ).attributedTo(authorId);
        changed = true;
        continue;
      }
      if (prev != null) {
        final newer = change.changedAt.isAfter(prev.changedAt);
        final sameMoment = change.changedAt.isAtSameMomentAs(prev.changedAt);
        // Aynı sürüm tekrar geldiyse (her eşitlemede gelir) dokunma.
        if (!newer && !(sameMoment && change.isDeletion && !prev.isDeletion)) continue;
        replacedImages.addAll(_mediaOf(prev.incoming).difference(_mediaOf(change.incoming)));
      }
      _pending[change.nodeId] = change;
      changed = true;
    }
    stats.pending = staged.length;
    if (_prunePending()) changed = true;
    if (changed) {
      _discardUnused(replacedImages);
      await _savePending();
    }
    if (changed || quiet.isNotEmpty) notifyListeners();
    return stats;
  }

  /// Bekleyen değişiklik bizdekine artık görünür bir şey katmıyorsa (aynı
  /// alanı biz daha sonra değiştirdik ya da aynısını yaptık) geçersizdir.
  /// Başka bir alanı düzenlemek onu düşürmez: kabul edilince ikisi birleşir.
  bool _prunePending() {
    final before = _pending.length;
    _pending.removeWhere((id, c) {
      final local = _byId[id];
      final inc = c.incoming;
      if (inc == null) {
        return local == null || local.updatedAt.millisecondsSinceEpoch > c.purgedAt!;
      }
      if (local == null) {
        final purgedAt = _tombstones[id];
        return purgedAt != null && purgedAt >= inc.updatedAt.millisecondsSinceEpoch;
      }
      return sameContent(local, mergeNode(local, inc));
    });
    return _pending.length != before;
  }

  /// Değişiklikleri uygular. Bizde olmayan üst klasörleri de beklemedeyse
  /// birlikte kabul edilir, yoksa eşya yersiz kalırdı.
  Future<void> acceptChanges(Iterable<String> ids) => _serial(() async {
        final accepting = ids.where(_pending.containsKey).toSet();
        if (accepting.isEmpty) return;
        accepting.addAll(pendingAncestors(accepting: accepting, local: _byId, pending: _pending));
        final result = mergeInventories(
          local: Map.of(_byId),
          localTombstones: Map.of(_tombstones),
          incoming: {
            for (final id in accepting) id: ?_pending[id]!.incoming,
          },
          incomingTombstones: {
            for (final id in accepting)
              if (_pending[id]!.purgedAt case final at? when _pending[id]!.isDeletion) id: at,
          },
          now: SyncClock.now(),
          author: authorId,
        );
        accepting.forEach(_pending.remove);
        await _applyMerge(result);
        _prunePending();
        await _savePending();
        notifyListeners();
        if (result.stats.relocated > 0) _touched();
      });

  Future<void> acceptAllChanges() => acceptChanges(_pending.keys.toList());

  /// Benim sürümüm kalsın: kayıt yeniden damgalanır, böylece karşıya da
  /// gider. Bizde hiç olmayan bir ekleme reddedilirse çöpe atılmış olarak
  /// kaydedilir; karşıda da çöpe gider, geri istenirse oradan alınır.
  Future<void> rejectChanges(Iterable<String> ids) => _serial(() async {
        final rejecting = ids.where(_pending.containsKey).toSet();
        if (rejecting.isEmpty) return;
        final now = SyncClock.now();
        // Yapana haber (onunla birlikte gelen içindekiler ayrıca sayılmaz).
        final notices = [
          for (final id in rejecting)
            if (_pending[id]!.author case final author? when author != authorId)
              Notice(
                id: _uuid.v4(),
                to: author,
                by: authorId ?? '',
                name: switch (_byId[id] ?? _pending[id]!.incoming) {
                  final Node n => nameOf(n),
                  null => '',
                },
                kind: describeChange(_pending[id]!, _byId[id]).kind.name,
                at: now.millisecondsSinceEpoch,
              ),
        ];
        rejecting.addAll(pendingDescendants(rejecting: rejecting, pending: _pending));
        final writes = <Node>[];
        final dropped = <String>{};
        for (final id in rejecting) {
          final change = _pending.remove(id)!;
          final local = _byId[id];
          final inc = change.incoming;
          if (local != null) {
            // Yalnızca reddedilen alanlar bizimkine döner; karşıdaki başka
            // bir alan değişikliği (kabul edilmişse) yerinde kalır.
            final rejected =
                inc == null ? const <NodeField>[] : differingFields(local, mergeNode(local, inc)).toList();
            var kept = bumpFields(local, rejected, now, by: authorId);
            // Ekler zamana göre değil tek tek birleşir: bizdekilerin geçerli kalması
            // için ayrıca damgalanırlar.
            if (inc != null && rejected.contains(NodeField.attachments)) kept = rejectAttachments(kept, inc, now);
            writes.add(kept);
          } else if (inc != null) {
            final top = !rejecting.contains(inc.parentId);
            if (top && !inc.isDeleted) {
              writes.add(stampChanges(inc, inc.copyWith(deletedAt: now, updatedAt: now, updatedBy: authorId), now));
            } else {
              writes.add(inc);
            }
          }
          dropped.addAll(_mediaOf(inc));
        }
        for (final n in writes) {
          _byId[n.id] = n;
        }
        _invalidate();
        await AppDatabase.instance.upsertAll(writes);
        _prunePending();
        await _savePending();
        _discardUnused(dropped);
        notifyListeners();
        _touched();
        if (notices.isNotEmpty) onRejected?.call(notices);
      });

  /// Geri çevrilen değişikliklerin haberi (ortak kullanım yapanlara iletir).
  void Function(List<Notice> notices)? onRejected;

  Future<void> rejectAllChanges() => rejectChanges(_pending.keys.toList());

  /// Ortaklıktan ayrılınca: artık kimsenin değişikliği beklenmiyor.
  Future<void> discardPendingChanges() => _serial(() async {
        if (_pending.isEmpty) return;
        final images = {for (final c in _pending.values) ..._mediaOf(c.incoming)};
        _pending.clear();
        await _savePending();
        _discardUnused(images);
        notifyListeners();
      });

  Future<void> _loadPending() async {
    _pending.clear();
    final text = await AppDatabase.instance.readMeta(_pendingKey);
    if (text == null || text.isEmpty) return;
    try {
      final list = jsonDecode(text);
      if (list is! List) return;
      for (final raw in list) {
        final c = PendingChange.fromJson(raw);
        if (c != null) _pending[c.nodeId] = c;
      }
    } on FormatException {
      return;
    }
    _prunePending();
  }

  Future<void> _savePending() => AppDatabase.instance.writeMeta(
        _pendingKey,
        jsonEncode([for (final c in _pending.values) c.toJson()]),
      );

  /// Bekleyen değişikliklerin resimleri de sayılır: değişiklik listesinde
  /// yeni fotoğraf onaydan önce görülebilsin.
  bool _referenced(String rel) =>
      _byId.values.any((n) => n.imagePath == rel) ||
      _pending.values.any((c) => c.incoming?.imagePath == rel);

  /// Özel kayıtların resmi karşıdan gelemez; sayılsa "eksik fotoğraf var" diye
  /// her duyuruda boşuna konuşulurdu.
  @override
  Set<String> missingImages() => {
        for (final n in [
          for (final n in _byId.values) if (!isPrivate(n.id)) n,
          for (final c in _pending.values) ?c.incoming,
        ])
          if (n.hasImage && isSafeImagePath(n.imagePath) && AppPaths.imageFile(n.imagePath) == null)
            n.imagePath!,
      };

  /// Yalnızca ortak bir kaydın işaret ettiği resimler verilir; aynı klasördeki
  /// profil resmi ya da yalnızca bende tutulan kaydın fotoğrafı paylaşılmaz.
  @override
  Future<Uint8List?> readImage(String rel) async {
    if (!isSafeImagePath(rel)) return null;
    if (!_outgoing().values.any((n) => n.imagePath == rel)) return null;
    final file = AppPaths.imageFile(rel);
    return file?.readAsBytes();
  }

  @override
  Future<bool> saveImage(String rel, Uint8List bytes) async {
    if (!isSafeImagePath(rel) || !_referenced(rel)) return false;
    if (AppPaths.imageFile(rel) != null) return true; // zaten var
    final file = File(AppPaths.abs(rel));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    AppPaths.forget(rel);
    notifyListeners();
    return true;
  }

  /// Eklerin diskte olmayan dosyaları (yol → beklenen boyut; 0: bilinmiyor).
  /// Resimlerdeki gibi: özel kayıtlarınki sayılmaz, bekleyen değişikliklerinki sayılır.
  @override
  Map<String, int> missingFiles() => {
        for (final n in [
          for (final n in _byId.values) if (!isPrivate(n.id)) n,
          for (final c in _pending.values) ?c.incoming,
        ])
          for (final a in n.attachments)
            if (a.file case final rel? when isSafeFilePath(rel) && AppPaths.imageFile(rel) == null) rel: a.size,
      };

  /// Yalnızca ortak bir kaydın eki verilir (bkz. [readImage]).
  @override
  File? outgoingFile(String rel) {
    if (!isSafeFilePath(rel)) return null;
    if (!_outgoing().values.any((n) => n.attachments.any((a) => a.file == rel))) return null;
    return AppPaths.imageFile(rel);
  }

  /// İndirilen ekin yazılacağı geçici dosya; [adoptFile] yerine koyar.
  @override
  File incomingFile(String rel) => File('${AppPaths.abs(rel)}.part');

  /// İndirme bitti: beklenen bir ekse ve boyutu tutuyorsa yerine konur.
  @override
  Future<bool> adoptFile(String rel, File temp) async {
    final wanted = missingFiles();
    final expected = wanted[rel];
    final length = await temp.exists() ? await temp.length() : -1;
    if (expected == null || length < 0 || length > Attachment.maxBytes || (expected > 0 && length != expected)) {
      try {
        if (length >= 0) await temp.delete();
      } on FileSystemException {
        // Geçici dosya; bir dahaki indirmede üstüne yazılır.
      }
      // Bu arada başka yoldan gelmişse sorun yok.
      return expected == null && AppPaths.imageFile(rel) != null;
    }
    await temp.rename(AppPaths.abs(rel));
    AppPaths.forget(rel);
    notifyListeners();
    return true;
  }

  /// Çöp kutusunu boşaltır. Kayıt başına ayrı yazım/haber yerine tek geçiş:
  /// 300 kayıtta işlem sayısı 300'den 1'e iner.
  Future<void> emptyTrash({bool now = false}) => _purge({
        for (final n in trash)
          if (_byId.containsKey(n.id)) ...subtreeIds(n.id),
      }, archive: !now);

  /// [nodeId] gercekten [targetId] altina tasinabilir mi? Zaten orada
  /// duruyorsa da false döner, boylece boş bırakma hedefleri sessiz kalir.
  bool canMove(String nodeId, String targetId) {
    final node = _byId[nodeId];
    if (node == null || node.isDeleted) return false;
    if (targetId == nodeId) return false;
    if (bucketKey(node) == targetId) return false; // zaten burada
    if (Roots.isVirtual(targetId)) return true;
    final target = _byId[targetId];
    if (target == null || !target.isContainer || target.isDeleted) return false;
    return !isSelfOrDescendant(nodeId, targetId); // kendi içine olmaz
  }

  /// [nodeId] kaydini [targetId] (sanal kök ya da klasör) altina taşır.
  /// Gecersiz hedeflerde false döner.
  Future<bool> move(String nodeId, String targetId) async {
    final node = _byId[nodeId];
    if (node == null) return false;
    if (!canMove(nodeId, targetId)) return false;
    if (targetId == Roots.lost) return markLost(nodeId);
    final isRoot = Roots.isVirtual(targetId);
    // Kayıp çekmecesinden bir yere konunca eşya bulunmuş olur.
    await commit(node.copyWith(
      parentId: isRoot ? null : targetId,
      clearParent: isRoot,
      inDrawer: targetId == Roots.drawer,
      sortIndex: _nextSortIndex(targetId),
      clearLost: true,
    ));
    return true;
  }

  /// Eşyanın adedini değiştirir. 0'da kayıt silinmez: tükenen sarf malzemesi
  /// yerinde durur, stok gelince aynı kayıttan sayı artırılır.
  /// Adet (kartta − / +). Farklı tarihli paketi olan eşyada azalan en eski
  /// paketten gider, artan en yeni pakete (raf ömrü varsa bugünün tarihli
  /// pakete) girer; bkz. `lots.dart`.
  Future<void> setQuantity(String nodeId, int quantity) async {
    final node = _byId[nodeId];
    if (node == null || node.isDeleted) return;
    var next = setQuantityByLots(node, quantity, DateTime.now());
    if (identical(next, node)) return;
    // Alınıp elle yerleştirildi (kartta +): artık "Yerleştirilecek" değil.
    if (node.isBought && quantity > (node.quantity ?? 0)) next = next.copyWith(clearBought: true, clearWanted: true);
    await commit(next);
  }

  /// Tarayıcının seri sayımında okunan eşya bir artar, kartın + düğmesi gibi ([setQuantity]: paket kuralı,
  /// adedi tutulmayan 1'den başlar). Klasör, çöpteki ya da olmayan kayıt sayılmaz (null); yoksa yeni adet.
  Future<int?> countOne(String id) async {
    final node = _byId[id];
    if (node == null || node.isContainer || !isLive(node)) return null;
    await setQuantity(id, (node.quantity ?? 0) + 1);
    return _byId[id]?.quantity;
  }

  /// Kartta + ile eklenen birimlerin tarihi farklıymış: [from] tarihli
  /// paketten [to] tarihli pakete taşınır.
  Future<void> redateUnits(String nodeId, int count, DateTime from, DateTime to) async {
    final node = _byId[nodeId];
    if (node == null) return;
    await commit(moveUnits(node, count, from, to));
  }

  /// Tarihi geçenleri atar (kalanlar yerinde); atılan birim sayısı döner.
  Future<int> discardExpiredUnits(String nodeId) async {
    final node = _byId[nodeId];
    if (node == null) return 0;
    final today = DateTime.now();
    final count = expiredUnits(node, today);
    if (count == 0) return 0;
    await commit(discardExpired(node, today));
    return count;
  }

  // ---------------------------------------------------------------- sık kullanılanlar

  /// Sık kullanılanlar, eklenme sırasıyla. Silinen ya da çöpe atılan kayıtlar
  /// listede kalsa da burada görünmez.
  /// Çöpteki bir klasörün içindekiler de düşer (çöp işareti yalnızca klasörün kendisinde).
  List<Node> get favorites => [
        for (final id in settings.favorites)
          if (_byId[id] case final n? when isLive(n)) n,
      ];

  bool isFavorite(String id) => settings.favorites.contains(id);

  /// Kaydı sık kullanılanlara ekler ya da çıkarır. Bu cihaza özeldir.
  Future<bool> toggleFavorite(String id) async {
    final list = [...settings.favorites];
    final added = !list.remove(id);
    if (added) list.add(id);
    await updateSettings(settings.copyWith(favorites: list));
    return added;
  }

  // ---------------------------------------------------------------- son dokunulanlar

  static const _recentLimit = 12;

  /// Bu cihazda son eklenen, düzenlenen ya da yeri değişen kayıtlar, en yeni
  /// önce: boş aramada "dün bir şey koydum, neredeydi" sorusunun cevabı.
  /// Sık kullanılanlar gibi cihaza özeldir; karşıdan gelen değişiklikler ve
  /// yalnızca sırası değişenler buraya girmez.
  List<Node> get recent => [
        for (final id in settings.recent)
          if (_byId[id] case final n? when isLive(n)) n,
      ];

  /// Haber vermez: her yazımın sonunda zaten haber veriliyor.
  Future<void> _noteRecent(Iterable<String> ids) async {
    final add = ids.toList();
    if (add.isEmpty) return;
    final next = [
      ...add,
      ...settings.recent.where((id) => !add.contains(id)),
    ].take(_recentLimit).toList();
    if (listEquals(next, settings.recent)) return;
    settings = settings.copyWith(recent: next);
    await AppDatabase.instance.writeMeta('recent', next.join(','));
  }

  // ---------------------------------------------------------------- yedek hatırlatması

  /// Son yedekten bu yana bu kadar geçince hatırlatılır.
  static const backupInterval = Duration(days: 30);

  /// Hiç yedek alınmadıysa ilk kayıttan bu kadar sonra.
  static const firstBackupAfter = Duration(days: 7);

  /// "Sonra" denince hatırlatma bu kadar susar.
  static const backupSnooze = Duration(days: 7);

  bool? _backupDueCache;

  /// Son dışa aktarmadan bu yana değişen kayıt sayısı (çöpe atılan ve
  /// kalıcı silinenler dahil). Hiç yedek alınmadıysa hepsi.
  int get changesSinceBackup {
    final since = settings.lastBackupAt?.millisecondsSinceEpoch;
    if (since == null) return _byId.length + _tombstones.length;
    return _byId.values.where((n) => n.updatedAt.millisecondsSinceEpoch > since).length +
        _tombstones.values.where((t) => t > since).length;
  }

  /// Yedek hatırlatmasının zamanı geldi mi. Sunucu yok: telefon kaybolur ya
  /// da bozulursa envanter de gider. Son yedekten (hiç alınmadıysa ilk
  /// kayıttan) bu yana yeterince zaman geçmiş ve o arada bir şey değişmişse
  /// sol menüde sakin bir hatırlatma çıkar. Birkaç kayıtlık yeni envanteri
  /// rahatsız etmez. Menü düğmesindeki nokta her çizimde sorduğu için önbellekli.
  bool get backupDue => _backupDueCache ??= backupDueAt(DateTime.now());

  bool backupDueAt(DateTime now) {
    if (_byId.values.where((n) => !n.isDeleted).length < 5) return false;
    final snoozed = settings.backupSnoozedAt;
    if (snoozed != null && now.difference(snoozed) < backupSnooze) return false;
    final last = settings.lastBackupAt;
    if (last != null) {
      return now.difference(last) >= backupInterval && changesSinceBackup > 0;
    }
    final first = _byId.values.map((n) => n.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
    return now.difference(first) >= firstBackupAfter;
  }

  /// Yedek dosyası bir yere verildi.
  Future<void> markBackedUp([DateTime? at]) =>
      updateSettings(settings.copyWith(lastBackupAt: at ?? DateTime.now()));

  Future<void> snoozeBackupReminder([DateTime? at]) =>
      updateSettings(settings.copyWith(backupSnoozedAt: at ?? DateTime.now()));

  // ---------------------------------------------------------------- tarihler

  /// Eşyanın uyarı süresi: kendi süresi, yoksa genel ayar.
  /// Eşyanın son kullanma uyarı süresi. Kendi süresi yoksa ömrünün dörtte biri,
  /// genel ayarı geçmeden: 3 ay önceden uyarı, 10 günlük yoğurdu alındığı gün
  /// "yaklaştı" diye işaretliyor, "Tarihi yaklaşanlar" hep dolu duruyordu. Ömür,
  /// alındığı (bilinmiyorsa eklendiği) günden son tarihe; 1 yıllık konserve yine
  /// 3 ay önceden uyarılır.
  TimeSpan warnSpanOf(Node n) {
    if (TimeSpan.parse(n.expiryWarn) case final own?) return own;
    final general = settings.expiryWarning;
    final end = n.effectiveExpiry;
    if (end == null) return general;
    final life = daysBetween(n.purchasedAt ?? n.createdAt, end);
    final quarter = life <= 4 ? 1 : (life / 4).round();
    // Genel süreye bir haftadan yakınsa genel süre: "91 gün" değil "3 ay" yazsın.
    return quarter < daysBetween(general.subtractFrom(end), end) - 7 ? TimeSpan(quarter, SpanUnit.day) : general;
  }

  /// Eşyanın son kullanma durumu; tarihi yoksa, klasörse ya da tükendiyse null
  /// (biten sarf malzemesinin tarihi kimseyi ilgilendirmez).
  ExpiryState? expiryOf(Node n, [DateTime? today]) {
    if (n.isContainer || n.quantity == 0) return null;
    final day = dateOnly(today ?? DateTime.now());
    final memo = _expiryMemo[n];
    if (memo != null && memo.$1 == day) return memo.$2;
    final end = n.effectiveExpiry;
    final state = end == null ? null : expiryStateOf(end, warnSpanOf(n), day);
    _expiryMemo[n] = (day, state);
    return state;
  }

  /// Hesaplanan son kullanma durumu: kaydın o haline, güne ve genel uyarı
  /// süresine bağlı. Her kart çiziminde ve her değişiklikte bütün tarihli
  /// eşyalar için baştan hesaplanıyordu (süre hesabı pahalı: ay ekleme çıkarma).
  /// [Node] değişmez; değişen kayıt yeni bir nesne olduğu için yalnızca o yeniden
  /// hesaplanır. Genel uyarı süresi değişince hepsi düşer ([updateSettings]).
  Expando<(DateTime, ExpiryState?)> _expiryMemo = Expando();

  _DateLists? _datesCache;

  /// Süresi geçen ve yaklaşanlar (tarih sırasıyla), garantisi olanlar
  /// (bitişe göre), tükenenler ve azalanlar (ada göre). Menüdeki sayılar her çizimde
  /// sorulduğu için günlük önbellekli; ağaç ya da ayar değişince düşer.
  _DateLists get _dates {
    final today = dateOnly(DateTime.now());
    final cached = _datesCache;
    if (cached != null && cached.day == today) return cached;
    final alerts = <Node>[];
    final warranties = <Node>[];
    final outOfStock = <Node>[];
    final low = <Node>[];
    final wanted = <Node>[];
    final services = <Node>[];
    for (final n in _byId.values) {
      if (n.isDeleted) continue;
      // Periyodik bakım klasörde de olabilir (araba, akvaryum); öteki listeler yalnızca eşyada.
      if (n.serviceEvery != null && n.servicedAt != null && isLive(n)) services.add(n);
      if (n.isContainer) continue;
      // Tarihi, garantisi, adedi ve liste işareti olmayan eşya (çoğu kayıt)
      // hiçbir listeye girmez: ona görünürlük ve süre hesabı yapılmaz.
      final relevant = n.quantity != null ||
          n.wantedAt != null ||
          n.expiresAt != null ||
          n.lots.isNotEmpty ||
          n.shelfLife != null ||
          n.warrantyEndsAt != null ||
          n.warranty != null;
      if (!relevant || !isLive(n)) continue;
      final state = expiryOf(n, today);
      if (state != null && state != ExpiryState.fine) alerts.add(n);
      if (n.effectiveWarrantyEnd != null) warranties.add(n);
      if (n.quantity == 0) outOfStock.add(n);
      if (n.isLow) low.add(n);
      if (n.isWanted) wanted.add(n);
    }
    alerts.sort((a, b) => a.effectiveExpiry!.compareTo(b.effectiveExpiry!));
    warranties.sort((a, b) => a.effectiveWarrantyEnd!.compareTo(b.effectiveWarrantyEnd!));
    int byName(Node a, Node b) => foldForSearch(nameOf(a)).compareTo(foldForSearch(nameOf(b)));
    outOfStock.sort(byName);
    low.sort(byName);
    wanted.sort((a, b) => a.wantedAt!.compareTo(b.wantedAt!));
    services.sort((a, b) => a.nextService!.compareTo(b.nextService!));
    return _datesCache = (
      day: today,
      alerts: alerts,
      warranties: warranties,
      outOfStock: outOfStock,
      low: low,
      wanted: wanted,
      services: services,
      serviceDue: [
        for (final n in services)
          if (n.serviceStateOn(today) != ExpiryState.fine) n,
      ],
    );
  }

  /// Son kullanma tarihi geçen ya da uyarı süresine giren eşyalar.
  List<Node> get expiryAlerts => _dates.alerts;

  /// Garantisi olan eşyalar, en erken biten önce.
  List<Node> get warranties => _dates.warranties;

  /// Periyodik bakımı olan kayıtlar (eşya ya da klasör), sonraki bakımı en yakın önce.
  List<Node> get serviceItems => _dates.services;

  /// Bakımı gecikmiş ya da zamanı yaklaşmış olanlar (bugün dahil; bkz. [Node.serviceStateOn]).
  List<Node> get serviceDue => _dates.serviceDue;

  /// Bakım yapıldı: son bakım günü [today] olur, geçmişe bir satır girer (o güne zaten satır
  /// varsa girmez: ikinci dokunuş çift kayıt açmasın). Satın alma, son kullanma ve garanti
  /// tarihlerine dokunmaz: bakım garantiyi uzatmaz, eşyanın son kullanma tarihi de değildir.
  Future<void> markServiced(String nodeId, [DateTime? today]) async {
    final n = _byId[nodeId];
    if (n == null) return;
    final day = dateOnly(today ?? DateTime.now());
    final logged = n.serviceLog.any((e) => e.day == day);
    await commit(n.copyWith(
      servicedAt: day,
      serviceLog: logged ? n.serviceLog : ServiceEntry.add(n.serviceLog, ServiceEntry(day)),
    ));
  }

  /// "Bakım yapıldı"nın geri alınması: son bakım günü ve geçmiş eski haline döner; bakımın
  /// planına ve kaydın başka alanlarına (arada değişmiş olabilir) dokunulmaz.
  Future<void> undoServiced(Node before) async {
    final n = _byId[before.id];
    if (n == null) return;
    await commit(n.copyWith(
      servicedAt: before.servicedAt,
      clearServiced: before.servicedAt == null,
      serviceLog: before.serviceLog,
    ));
  }

  // ---------------------------------------------------------------- alışveriş listesi

  /// Eşya neden alınmalı: tükendi, azaldı ya da tarihi geçti; hiçbiri değilse null.
  ///
  /// "Tarihi geçti" ancak elde tarihi geçmemiş paket kalmadıysa: 5 yoğurdun biri
  /// bozulduysa yenisini almak gerekmez (azalınca en az adet söyler).
  ShoppingReason? shoppingReason(Node n, [DateTime? today]) {
    if (n.isContainer) return null;
    if (n.quantity == 0) return ShoppingReason.out;
    if (n.isLow) return ShoppingReason.low;
    final last = n.lastExpiry;
    if (last != null && dateOnly(today ?? DateTime.now()).isAfter(dateOnly(last))) return ShoppingReason.expired;
    return null;
  }

  /// Alınması gerekenler, bu sırayla: tükenenler, azalanlar, tarihi geçenler.
  List<Node> get _needs => _derived()._needsCache ??= {
        ..._dates.outOfStock,
        ..._dates.low,
        for (final n in _dates.alerts)
          if (shoppingReason(n) == ShoppingReason.expired) n,
      }.toList();

  // [_dates]'ten türeyen listeler de onunla birlikte bir kez kurulur: menüdeki
  // sayılar, kenar kulpları ve widget her çizimde sorar. Dönen listeler
  // önbellektedir, değiştirilmemeli.
  List<Node>? _derivedFor;
  List<Node>? _needsCache;
  List<Node>? _shoppingCache;
  List<Node>? _suggestionsCache;
  List<Node>? _expiredCache;

  /// [_dates] yeniden kurulduysa türeyenleri düşürür.
  InventoryStore _derived() {
    final alerts = _dates.alerts;
    if (!identical(alerts, _derivedFor)) {
      _derivedFor = alerts;
      _needsCache = _shoppingCache = _suggestionsCache = _expiredCache = null;
    }
    return this;
  }

  /// Alışveriş listesi: kullanıcının ekledikleri ve "listeye kendiliğinden
  /// ekle" ayarı açık olup biten, azalan ya da tarihi geçen eşyalar
  /// ([Node.autoShop]). Alınması gerekenler önce (tükenen, azalan, tarihi
  /// geçen), sonra eklenme sırasıyla ötekiler. Kendiliğinden girenler alınınca
  /// (durumları düzelince) kendiliğinden düşer.
  /// Markette işaretlenenler ([Node.isBought]) listeden düşer, "Yerleştirilecek"te durur.
  List<Node> get shoppingItems => _derived()._shoppingCache ??= {
        for (final n in _needs)
          if ((n.autoShop || n.isWanted) && !n.isBought) n,
        for (final n in _dates.wanted)
          if (!n.isBought) n,
      }.toList();

  /// Öneriler: alınması gereken ama listede olmayanlar (ayarı kapalı olanlar).
  /// Kullanıcı ekler ya da eklemez; kendiliğinden listeye girmez.
  List<Node> get shoppingSuggestions => _derived()._suggestionsCache ??= [
        for (final n in _needs)
          if (!n.autoShop && !n.isWanted && !n.isBought) n,
      ];

  /// Markette "Aldım" denip evde adedi ve tarihi girilecek olanlar, ilk alınan önce.
  List<Node> get toPutAway => [
        for (final n in _byId.values)
          if (n.isBought && !n.isContainer && isLive(n)) n,
      ]..sort((a, b) => a.boughtAt!.compareTo(b.boughtAt!));

  /// Diske milisaniyeyle yazılan an: bellekteki de öyle olsun (karşılaştırmalar
  /// yeniden açılışta değişmesin).
  static DateTime _msNow() => DateTime.fromMillisecondsSinceEpoch(SyncClock.now().millisecondsSinceEpoch);

  /// Markette: alındı, listeden düşer; adet ve tarih evde "Yerleştir"de.
  Future<void> markBought(String nodeId) async {
    final n = _byId[nodeId];
    if (n == null || n.isContainer || n.isBought) return;
    await commit(n.copyWith(boughtAt: _msNow(), clearBuying: true));
  }

  /// "Aldım" yanlışlıkla: yeniden listede.
  Future<void> unmarkBought(String nodeId) async {
    final n = _byId[nodeId];
    if (n == null || !n.isBought) return;
    await commit(n.copyWith(clearBought: true));
  }

  /// "Alıyorum": ortak listede ötekiler kimin aldığını görür (bir gün geçerli).
  Future<void> setBuying(String nodeId, bool on) async {
    final n = _byId[nodeId];
    if (n == null || n.isContainer) return;
    await commit(on ? n.copyWith(buyingBy: authorId ?? '', buyingAt: _msNow()) : n.copyWith(clearBuying: true));
  }

  /// Son kullanma tarihi geçip hâlâ yerinde duranlar (sık kullanılanlar gibi
  /// yalnızca bir işaret; eşya yerinden kıpırdamaz), en eski tarih önce.
  /// Yerinden çıkarılınca listeden düşer: çöpe atılınca, çekmeceye alınınca,
  /// kayıp bildirilince ya da adedi 0'a inince (biten eşyanın tarihi yok sayılır).
  List<Node> get expiredItems => _derived()._expiredCache ??= [
        for (final n in _dates.alerts)
          if (!n.inDrawer && !n.isLost && expiryOf(n) == ExpiryState.expired) n,
      ];

  /// Emanete / ödünç verilmiş canlı kayıtlar (en yeni verilen üstte).
  List<Node> get borrowedItems =>
      _byId.values.where((n) => isLive(n) && n.isBorrowed).toList()
        ..sort((a, b) => (b.borrowedAt ?? b.updatedAt).compareTo(a.borrowedAt ?? a.updatedAt));

  /// İade tarihi geçmiş emanetler.
  List<Node> get overdueBorrowedItems =>
      _byId.values.where((n) => isLive(n) && n.isBorrowOverdue).toList();

  bool get hasOverdueBorrow => overdueBorrowedItems.isNotEmpty;

  /// Daha önce girilmiş ödünç alan kişi adları (hızlı seçim çipleri için).
  List<String> get knownBorrowers {
    final names = <String>{};
    for (final n in _byId.values) {
      if (n.borrowedTo case final b? when b.trim().isNotEmpty) {
        names.add(b.trim());
      }
    }
    return names.toList()..sort();
  }

  int get shoppingCount => shoppingItems.length;

  /// Alışveriş listesine ekler ya da listeden çıkarır.
  Future<void> setWanted(String nodeId, bool wanted) async {
    final n = _byId[nodeId];
    if (n == null || n.isContainer || n.isWanted == wanted) return;
    await commit(wanted ? n.copyWith(wantedAt: _msNow()) : n.copyWith(clearWanted: true, clearBuying: true));
  }

  /// Adet tutulmayan eşya alındı (ya da yerleştirildi): listeden düşer.
  Future<void> bought(String nodeId) async {
    final n = _byId[nodeId];
    if (n == null || n.isContainer) return;
    await commit(n.copyWith(clearWanted: true, clearBuying: true, clearBought: true));
  }

  /// "Aldım"ın geri alınması: adet, tarih ve listedeki yeri eski haline döner.
  Future<void> undoBought(Node before) async {
    final n = _byId[before.id];
    if (n == null) return;
    await commit(n.copyWith(
      quantity: before.quantity,
      clearQuantity: before.quantity == null,
      lots: before.lots,
      purchasedAt: before.purchasedAt,
      clearPurchased: before.purchasedAt == null,
      expiresAt: before.expiresAt,
      clearExpires: before.expiresAt == null,
      wantedAt: before.wantedAt,
      clearWanted: before.wantedAt == null,
      buyingBy: before.buyingBy,
      buyingAt: before.buyingAt,
      clearBuying: before.buyingBy == null,
      boughtAt: before.boughtAt,
      clearBought: before.boughtAt == null,
    ));
  }

  /// Son kullanma tarihi [until] gününe kadar (dahil) dolan ya da dolmuş
  /// eşyalar, en erken önce; tükenenler hariç ([expiryOf] gibi). Ana ekran
  /// widget'ı bunlarla, gün dönünce listeyi uygulama açılmadan da tazeler.
  /// Paketli eşyada en yeni paketin tarihi sayılır ("hepsi geçti").
  List<Node> expiringBy(DateTime until) {
    final last = dateOnly(until);
    return [
      for (final n in _byId.values)
        if (!n.isContainer && !n.isDeleted && n.quantity != 0 && isLive(n))
          if (n.lastExpiry case final end? when !dateOnly(end).isAfter(last)) n,
    ]..sort((a, b) => a.lastExpiry!.compareTo(b.lastExpiry!));
  }

  /// [count] tane alındı: elde kalanın üstüne eklenir (azalan eşyada 2 kalmışsa
  /// 6 alınınca 8 olur) ve alışveriş listesinden düşer.
  ///
  /// [expires] verilirse alınanlar o tarihli ayrı bir paket olur (eldekiler
  /// kendi tarihiyle kalır); verilmezse raf ömrü varsa bugünün tarihli pakete,
  /// yoksa en yeni pakete girer. Satın alma tarihi bugün olur.
  Future<void> restock(String nodeId, int count, {DateTime? expires}) async {
    final n = _byId[nodeId];
    if (n == null || count <= 0) return;
    final today = DateTime.now();
    var next = expires != null ? addLot(n, count, expires) : setQuantityByLots(n, (n.quantity ?? 0) + count, today);
    if (expires != null || n.shelfLife != null) next = next.copyWith(purchasedAt: dateOnly(today));
    await commit(next.copyWith(clearWanted: true, clearBuying: true, clearBought: true));
  }

  /// Hepsinin tarihi geçmiş adetli eşyanın yenisi alındı: tarihi geçenler
  /// atılır, [count] yenisi [expires] tarihli (verilmezse raf ömründen) girer.
  Future<void> replaceExpired(String nodeId, int count, {DateTime? expires}) async {
    final n = _byId[nodeId];
    if (n == null) return;
    var kept = discardExpired(n, DateTime.now());
    // Tarihi söylenmediyse yeniler eskinin geçmiş tarihini almasın: tarihsiz kalır.
    if (expires == null && n.shelfLife == null && kept.quantity == 0) kept = kept.copyWith(clearExpires: true);
    await commit(kept);
    await restock(nodeId, count, expires: expires);
  }

  /// Tarihi geçen eşyanın yenisi alındı: satın alma bugün, paketteki eski tarih
  /// silinir (yenisinin tarihi girilmeli). Raf ömrü varsa yeni tarih ondan
  /// kendiliğinden hesaplanır (muz, elma).
  Future<void> replaced(String nodeId, [DateTime? today]) async {
    final n = _byId[nodeId];
    if (n == null || n.isDeleted) return;
    await commit(n.copyWith(
      purchasedAt: dateOnly(today ?? DateTime.now()),
      clearExpires: true,
      clearWanted: true,
      clearBuying: true,
      clearBought: true,
    ));
  }

  /// Telefon bildirimlerinin planı: çöpte ya da tükenmiş olmayan eşyalar.
  List<DateAlert> dateAlerts(DateTime now, {int maxDays = 30}) => planDateAlerts(
        [
          for (final n in _byId.values)
            if (!n.isContainer && n.quantity != 0 && n.hasDates && isLive(n)) n,
        ],
        services: serviceItems,
        warnOf: warnSpanOf,
        now: now,
        maxDays: maxDays,
      );

  // ---------------------------------------------------------------- toplu işlemler

  /// Seçilenlerden, üstü de seçilmiş olanlar düşer: klasörle birlikte zaten
  /// giderler. Yoksa kutu taşınırken içinden seçilen eşya kutudan çıkarılırdı.
  /// Destedeki sırayla döner, dokunulma sırasıyla değil: taşınanlar hedefte
  /// de kendi aralarındaki sırayı korusun.
  List<Node> selectionRoots(Iterable<String> ids) {
    final chosen = ids.toSet();
    return [
      for (final id in chosen)
        if (_byId[id] case final n? when !n.isDeleted && !ancestorsOf(id).any((a) => chosen.contains(a.id))) n,
    ]..sort(_deckOrder);
  }

  /// Seçilen kayıtları [targetId] (sanal kök ya da klasör) altına taşır; tek
  /// yazım, tek haber. Taşınamayanlar (hedefin kendisi, kendi içine giden
  /// klasör, zaten orada olan) sessizce atlanır. Taşınanların önceki hali
  /// döner; [restorePlacements] onlarla geri alır.
  Future<List<Node>> moveMany(Iterable<String> ids, String targetId) async {
    if (targetId == Roots.lost) return const [];
    final isRoot = Roots.isVirtual(targetId);
    final now = SyncClock.now();
    var next = _nextSortIndex(targetId);
    final before = <Node>[];
    final updated = <Node>[];
    for (final n in selectionRoots(ids)) {
      if (!canMove(n.id, targetId)) continue;
      before.add(n);
      updated.add(n.copyWith(
        parentId: isRoot ? null : targetId,
        clearParent: isRoot,
        inDrawer: targetId == Roots.drawer,
        clearLost: true,
        clearHeld: true,
        sortIndex: next++,
        updatedAt: now,
        updatedBy: authorId,
      ));
    }
    if (updated.isEmpty) return const [];
    await _writeMany(updated, recent: true);
    return before;
  }

  /// Toplu taşımanın geri alınması: her kayıt eski yerine ve eski sırasına
  /// döner, kayıpsa yeniden kayıp olur. Sıradan [move] ile geri koymak kaydı
  /// seviyenin sonuna ekliyordu; kartlar geri gelse de dizilişleri bozuluyordu.
  /// Arada eski yeri çöpe gittiyse ya da kayıt oraya artık giremiyorsa (kendi
  /// içine) olduğu yerde kalır.
  Future<void> restorePlacements(List<Node> before) async {
    final now = SyncClock.now();
    final updated = <Node>[];
    for (final old in before) {
      final n = _byId[old.id];
      if (n == null || n.isDeleted) continue;
      final parent = old.parentId;
      if (parent != null) {
        final p = _byId[parent];
        if (p == null || !isLive(p) || isSelfOrDescendant(n.id, parent)) continue;
      }
      updated.add(n.copyWith(
        parentId: parent,
        clearParent: parent == null,
        inDrawer: old.inDrawer,
        lostAt: old.lostAt,
        lostFrom: old.lostFrom,
        clearLost: !old.isLost,
        heldBy: old.heldBy,
        clearHeld: old.heldBy == null,
        sortIndex: old.sortIndex,
        updatedAt: now,
        updatedBy: authorId,
      ));
    }
    if (updated.isEmpty) return;
    await _writeMany(updated);
  }

  /// Seçilenleri çöp kutusuna atar. Klasörün içindekiler ayrıca işaretlenmez.
  Future<List<String>> trashMany(Iterable<String> ids) async {
    final now = SyncClock.now();
    final updated = [
      for (final n in selectionRoots(ids)) n.copyWith(deletedAt: now, updatedAt: now, updatedBy: authorId),
    ];
    if (updated.isEmpty) return const [];
    await _writeMany(updated);
    return [for (final n in updated) n.id];
  }

  /// [trashMany]'nin geri alınması.
  Future<void> restoreMany(Iterable<String> ids) async {
    for (final id in ids) {
      await restore(id);
    }
  }

  /// Yerel bir yazımın grup zamanları: bizdekinden farklı olan gruplar
  /// kaydın yeni zamanını alır. Her yazım bundan geçmeli; zamanı ilerlemeyen
  /// grup eşitlemede karşıdaki eski değere yenilirdi.
  Node _stamped(Node n) => stampChanges(_byId[n.id], n, n.updatedAt);

  Future<void> _writeMany(List<Node> changes, {bool recent = false}) async {
    final updated = [for (final n in changes) _stamped(n)];
    for (final n in updated) {
      _byId[n.id] = n;
    }
    _invalidate();
    await AppDatabase.instance.upsertAll(updated);
    if (_prunePending()) await _savePending();
    if (recent) await _noteRecent([for (final n in updated) n.id]);
    notifyListeners();
    _touched();
  }

  /// Klasörün yeri doldu mu. Kayıt sayısından bağımsızdır: kaydı olmayan
  /// eşyalarla dolmuş olabilir. Yer ararken kartta görünür.
  Future<void> setFull(String nodeId, bool full) async {
    final node = _byId[nodeId];
    if (node == null || node.isDeleted || !node.isContainer || node.isFull == full) return;
    await commit(node.copyWith(isFull: full));
  }

  /// Yerinde bulunamadı: kayıp çekmecesine alınır, son yeri saklanır.
  /// Ortak kullanımda diğerlerine onaysız ulaşır ve bildirim olarak görünür.
  Future<bool> markLost(String nodeId) async {
    final node = _byId[nodeId];
    if (node == null || node.isDeleted || node.isLost) return false;
    await commit(node.copyWith(
      clearParent: true,
      inDrawer: false,
      lostAt: SyncClock.now(),
      lostFrom: node.parentId,
      sortIndex: 0,
    ));
    return true;
  }

  /// Sürükleyip bırakılan kartı [parentId] listesinde [index] sırasına koyar;
  /// başka bir yerden geldiyse önce oraya taşır. Klasör ve eşyalar ayrı
  /// gruplanıyorsa sıralama kendi grubu içinde kalır (sıralama zaten türe göre).
  Future<bool> moveToIndex(String nodeId, String parentId, int index) async {
    final node = _byId[nodeId];
    if (node == null || node.isDeleted) return false;
    var target = index;
    if (bucketKey(node) != parentId) {
      if (!await move(nodeId, parentId)) return false;
    } else {
      // Kart zaten listede: önünden çıkacağı için hedef bir geri kayar.
      final at = childrenOf(parentId).indexWhere((n) => n.id == nodeId);
      if (at >= 0 && at < target) target -= 1;
    }
    final items = childrenOf(parentId);
    final from = items.indexWhere((n) => n.id == nodeId);
    if (from < 0) return false;
    final to = target.clamp(0, items.length - 1);
    if (from == to) return true;
    await reorder(parentId, from, to);
    return true;
  }

  /// [folderId] klasörünün içindekileri [targetId] seviyesine aktarılabilir mi?
  /// Klasörün kendisi yerinde kaldığı için hedef, klasörün kendi alt ağacı
  /// olamaz; boş klasörde aktaracak bir şey yoktur.
  bool canTransferContents(String folderId, String targetId) {
    final folder = _byId[folderId];
    if (folder == null || folder.isDeleted || !folder.isContainer) return false;
    if (targetId == folderId || targetId == Roots.lost) return false;
    if (childrenOf(folderId).isEmpty) return false;
    // Hedef klasörün kendi içindeyse taşımak ağacı bozardı.
    if (!Roots.isVirtual(targetId)) {
      final target = _byId[targetId];
      if (target == null || target.isDeleted || !target.isContainer) return false;
      if (isSelfOrDescendant(folderId, targetId)) return false;
    }
    return true;
  }

  /// Klasörün içindekileri [targetId] seviyesine taşır; klasörün kendisi
  /// yerinde kalır (boşalır). [index] verilirse o sıraya girerler. Taşınan
  /// kayıt sayısını döner.
  Future<int> moveContents(String folderId, String targetId, {int? index}) async {
    if (!canTransferContents(folderId, targetId)) return 0;
    final moving = childrenOf(folderId);
    final movingIds = {for (final n in moving) n.id};
    final isRoot = Roots.isVirtual(targetId);
    final now = SyncClock.now();

    // Hedefteki sıra: taşınanlar istenen yere sokulur, sonra bütün seviyeye
    // baştan sıra numarası verilir ([reorder] ile aynı kural).
    final order = [...childrenOf(targetId)];
    order.insertAll((index ?? order.length).clamp(0, order.length), moving);

    final updated = <Node>[];
    for (var i = 0; i < order.length; i++) {
      final n = order[i];
      final moved = movingIds.contains(n.id);
      if (!moved && n.sortIndex == i) continue;
      updated.add(moved
          ? n.copyWith(
              parentId: isRoot ? null : targetId,
              clearParent: isRoot,
              inDrawer: targetId == Roots.drawer,
              clearLost: true,
              clearHeld: true,
              sortIndex: i.toDouble(),
              updatedAt: now,
              updatedBy: authorId,
            )
          : n.copyWith(sortIndex: i.toDouble(), updatedAt: now, updatedBy: authorId));
    }
    updated.setAll(0, updated.map(_stamped).toList());
    for (final n in updated) {
      _byId[n.id] = n;
    }
    _invalidate();
    await AppDatabase.instance.upsertAll(updated);
    if (_prunePending()) await _savePending();
    await _noteRecent(movingIds);
    notifyListeners();
    _touched();
    return moving.length;
  }

  /// Destede suruklemeli sıralama.
  Future<void> reorder(String parentId, int oldIndex, int newIndex) async {
    // Önbellekteki liste değiştirilmez; kopyası sıralanır.
    final items = [...childrenOf(parentId)];
    if (oldIndex < 0 || oldIndex >= items.length) return;
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex.clamp(0, items.length), moved);
    final updated = <Node>[];
    final now = SyncClock.now();
    for (var i = 0; i < items.length; i++) {
      if (items[i].sortIndex != i) {
        // Zaman damgası da değişir ki sıralama ortak kullanımda karşıya geçsin.
        final n = _stamped(items[i].copyWith(sortIndex: i.toDouble(), updatedAt: now, updatedBy: authorId));
        _byId[n.id] = n;
        updated.add(n);
      }
    }
    _invalidate();
    await AppDatabase.instance.upsertAll(updated);
    if (_prunePending()) await _savePending();
    notifyListeners();
    _touched();
  }

  /// Deste kenarda kendiliğinden kayıyor. Kartların üzerinde bekleyince içine
  /// girme o sırada çalışmaz: parmak duruyor, altından kartlar geçiyor.
  /// Yeniden çizim gerektirmediği için haber verilmez.
  bool edgeScrolling = false;

  void setDragging(String? id) {
    if (draggingId == id) return;
    draggingId = id;
    if (id == null) edgeScrolling = false;
    // Ağaç değişmedi: önbellekler (çocuk indeksi, tarih listeleri, damga) dursun.
    // Her haber onları düşürdüğü için sürüklemeyi başlatmak ve bırakmak bütün
    // envanteri iki kez baştan taratıyordu.
    _notifyKeepingCaches();
  }

  /// Kayıtları ve ayarları değiştirmeyen arayüz durumu için haber.
  void _notifyKeepingCaches() => super.notifyListeners();

  /// Açık olan seviyeyi hatırlar: uygulama yeniden açılınca kullanıcı
  /// kaldığı yerden devam etsin. Ekranda bir şey değiştirmediği için
  /// dinleyicilere haber verilmez; yalnızca tek bir ayar satırı yazılır.
  Future<void> rememberLevel(String levelId) async {
    final node = _byId[levelId];
    // Yalnızca gerçek, duran bir klasör (ya da ana ekran) hatırlanır.
    final keep = levelId == Roots.home || (node != null && node.isContainer && isLive(node));
    final next = keep && levelId != Roots.home ? levelId : null;
    if (settings.lastLevel == next) return;
    settings = settings.copyWith(lastLevel: next, clearLastLevel: next == null);
    await AppDatabase.instance.writeMeta('last_level', next ?? '');
  }

  Future<void> updateSettings(AppSettings next) async {
    if (next.expiryWarning != settings.expiryWarning) _expiryMemo = Expando();
    settings = next;
    strings = AppStrings.forLanguage(next.language);
    await next.persist();
    notifyListeners();
  }
}

typedef _DateLists = ({
  DateTime day,
  List<Node> alerts,
  List<Node> warranties,
  List<Node> outOfStock,
  List<Node> low,
  List<Node> wanted,
  List<Node> services,
  List<Node> serviceDue,
});

/// Eşya alışveriş listesine neden girer (ya da önerilir).
enum ShoppingReason { out, low, expired }

/// Agaca her yerden erişim. Tum ağaç tek notifier oldugu için dinleyen
/// widget'lar degisimde birlikte tazelenir.
class InventoryScope extends InheritedNotifier<InventoryStore> {
  const InventoryScope({super.key, required InventoryStore store, required super.child})
      : super(notifier: store);

  static InventoryStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<InventoryScope>();
    assert(scope != null, 'InventoryScope agacta bulunamadi');
    return scope!.notifier!;
  }

  /// Yeniden cizime abone olmadan sadece okuma/yazma için.
  static InventoryStore read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<InventoryScope>();
    assert(scope != null, 'InventoryScope agacta bulunamadi');
    return scope!.notifier!;
  }
}
