import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

/// Bu cihazdaki envanterlerden biri (Obsidian'daki kasa gibi). Her envanterin
/// kendi veritabanı, fotoğraf klasörü, ortak kullanımı ve cihaza özel
/// listeleri (sık kullanılanlar, son açık seviye...) vardır; biri açıkken
/// ötekiler dokunulmadan durur.
class InventoryEntry {
  const InventoryEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    this.openedAt,
    this.count = 0,
    this.alerts = const [],
    this.shared = false,
    this.backedUpAt,
    this.unbacked = 0,
    this.backupKnown = false,
    this.deletedAt,
    this.shopping = const [],
    this.color,
    this.glyph,
    this.pending = 0,
  });

  final String id;

  /// Kullanıcının verdiği ad; ilk envanterde boş olabilir (arayüz "Envanter" der).
  final String name;
  final DateTime createdAt;
  final DateTime? openedAt;

  /// Kapanırken kayıt sayısı: liste açık olmayan envanteri açmadan gösterir.
  final int count;

  /// Kapanırken hesaplanan yaklaşan tarih bildirimleri: envanter kapalıyken de
  /// sütün son günü haber verilsin (bkz. `DateNotifier`).
  final List<SavedAlert> alerts;

  /// Kapanırken başkalarıyla paylaşılıyor muydu: silerken önce diğerlerine
  /// haber verilmesi gerekir (bkz. envanter silme akışı).
  final bool shared;

  /// Son yedeği (kapalı envanterin listesinde gösterilir).
  final DateTime? backedUpAt;

  /// Kapanırken son yedekten sonra değişen kayıt sayısı.
  final int unbacked;

  /// Yedek bilgisi kapanırken yazıldı mı. Bu bilgiden önce kapanmış envanterin
  /// yedeği bilinmez: "yedeği yok" demek yanlış olabilir.
  final bool backupKnown;

  /// İçinde bir şey var ve yedeği yok, eski ya da bilinmiyor.
  bool get needsBackup => count > 0 && (!backupKnown || backedUpAt == null || unbacked > 0);

  /// Silindiği an: Silinenler'de 30 gün durur, geri getirilebilir.
  final DateTime? deletedAt;

  /// Kapanırken alışveriş listesi: bütün envanterlerin listesi tek sayfada ve
  /// widget'ta görünsün (Ev ile Yazlık'ı birlikte kullanan için).
  final List<SavedShop> shopping;

  /// Kullanıcının bu envantere seçtiği renk (kart paletinden) ve amblem (kart
  /// simgelerinin anahtarı): "Ev" ile "Atölye" başlıkta ve listede bir bakışta
  /// ayrılsın. Seçilmediyse null. Bu cihaza özel: paylaşılan envanterde
  /// herkes kendi rengini seçer (ad gibi ağa gitmez).
  final int? color;
  final String? glyph;

  bool get hasLook => color != null || glyph != null;

  /// Kapanırken (ya da arka planda eşitlenince) onay bekleyen değişiklik sayısı:
  /// envanter listesinde işaret görünsün, açılmadan anlaşılsın.
  final int pending;

  /// [from]'daki özet bilgileri (envanter kapanırken ya da arka planda eşitlenince
  /// hesaplananlar) bu kayda taşır; ad, renk, açılış zamanı gibi bu cihazda
  /// belirlenenler olduğu gibi kalır.
  InventoryEntry withSummaryOf(InventoryEntry from) => InventoryEntry(
        id: id,
        name: name,
        createdAt: createdAt,
        openedAt: openedAt,
        count: from.count,
        alerts: from.alerts,
        shared: from.shared,
        backedUpAt: from.backedUpAt ?? backedUpAt,
        unbacked: from.unbacked,
        backupKnown: from.backupKnown || backupKnown,
        deletedAt: deletedAt,
        shopping: from.shopping,
        color: color,
        glyph: glyph,
        pending: from.pending,
      );

  InventoryEntry copyWith({
    String? name,
    DateTime? openedAt,
    int? count,
    List<SavedAlert>? alerts,
    bool? shared,
    DateTime? backedUpAt,
    int? unbacked,
    bool? backupKnown,
    DateTime? deletedAt,
    bool clearDeleted = false,
    List<SavedShop>? shopping,
    int? color,
    String? glyph,
    bool clearColor = false,
    bool clearGlyph = false,
    int? pending,
  }) =>
      InventoryEntry(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        openedAt: openedAt ?? this.openedAt,
        count: count ?? this.count,
        alerts: alerts ?? this.alerts,
        shared: shared ?? this.shared,
        backedUpAt: backedUpAt ?? this.backedUpAt,
        unbacked: unbacked ?? this.unbacked,
        backupKnown: backupKnown ?? this.backupKnown,
        deletedAt: clearDeleted ? null : (deletedAt ?? this.deletedAt),
        shopping: shopping ?? this.shopping,
        color: clearColor ? null : (color ?? this.color),
        glyph: clearGlyph ? null : (glyph ?? this.glyph),
        pending: pending ?? this.pending,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.millisecondsSinceEpoch,
        if (openedAt != null) 'openedAt': openedAt!.millisecondsSinceEpoch,
        'count': count,
        if (alerts.isNotEmpty) 'alerts': [for (final a in alerts) a.toJson()],
        if (shared) 'shared': true,
        if (backedUpAt != null) 'backedUpAt': backedUpAt!.millisecondsSinceEpoch,
        if (unbacked > 0) 'unbacked': unbacked,
        if (backupKnown) 'backupKnown': true,
        if (deletedAt != null) 'deletedAt': deletedAt!.millisecondsSinceEpoch,
        if (shopping.isNotEmpty) 'shopping': [for (final x in shopping) x.toJson()],
        if (color != null) 'color': color,
        if (glyph != null) 'glyph': glyph,
        if (pending > 0) 'pending': pending,
      };

  static InventoryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty || !_safeId.hasMatch(id)) return null;
    final created = raw['createdAt'];
    final opened = raw['openedAt'];
    final count = raw['count'];
    final alerts = raw['alerts'];
    DateTime? time(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return InventoryEntry(
      id: id,
      name: raw['name'] is String ? raw['name'] as String : '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(created is int ? created : 0),
      openedAt: opened is int ? DateTime.fromMillisecondsSinceEpoch(opened) : null,
      count: count is int ? count : 0,
      alerts: [
        if (alerts is List)
          for (final a in alerts) ?SavedAlert.fromJson(a),
      ],
      shared: raw['shared'] == true,
      backedUpAt: time(raw['backedUpAt']),
      unbacked: raw['unbacked'] is int ? raw['unbacked'] as int : 0,
      backupKnown: raw['backupKnown'] == true,
      deletedAt: time(raw['deletedAt']),
      shopping: [
        if (raw['shopping'] is List)
          for (final x in raw['shopping'] as List) ?SavedShop.fromJson(x),
      ],
      color: raw['color'] is int ? raw['color'] as int : null,
      glyph: raw['glyph'] is String && _safeGlyph.hasMatch(raw['glyph'] as String) ? raw['glyph'] as String : null,
      pending: raw['pending'] is int && (raw['pending'] as int) > 0 ? raw['pending'] as int : 0,
    );
  }

  /// Amblem bir simge anahtarıdır; tanınmayan anahtar gösterilirken varsayılana düşer.
  static final _safeGlyph = RegExp(r'^[a-z_]{1,24}$');

  /// Kimlik dosya adına girer: yalnızca güvenli karakterler.
  static final _safeId = RegExp(r'^[A-Za-z0-9-]+$');
}

/// Kapalı bir envanterin alışveriş listesindeki bir eşya: ad, neden ("2 kaldı")
/// ve durumu (widget'taki renk: out, low, expired, wanted).
class SavedShop {
  const SavedShop({required this.id, required this.name, required this.note, required this.kind});

  final String id;
  final String name;
  final String note;
  final String kind;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'note': note, 'kind': kind};

  static SavedShop? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final note = raw['note'];
    final kind = raw['kind'];
    if (id is! String || name is! String || note is! String || kind is! String) return null;
    return SavedShop(id: id, name: name, note: note, kind: kind);
  }
}

/// Kapalı bir envanterde aranabilen bir kayıt (kapanırken yazılan dizinden).
class IndexedRecord {
  const IndexedRecord({
    required this.id,
    required this.name,
    required this.container,
    required this.path,
    this.note = '',
    this.place = '',
    this.quantity,
    this.barcode,
    this.attachments = const [],
  });

  final String id;
  final String name;
  final bool container;

  /// Ürün barkodu: kapalı envanterdeki eşya da okutunca bulunsun.
  final String? barcode;

  /// Bulunduğu yer ("Garaj › Raf 2").
  final String path;
  final String note;
  final String place;
  final int? quantity;

  /// Eklerin adları: kılavuz/fatura kapalı envanterdeyken de aramayla çıksın.
  final List<String> attachments;

  Map<String, Object?> toJson() => {
        'id': id,
        'n': name,
        if (container) 'c': true,
        'p': path,
        if (note.isNotEmpty) 't': note,
        if (place.isNotEmpty) 'l': place,
        'q': ?quantity,
        'b': ?barcode,
        if (attachments.isNotEmpty) 'a': attachments,
      };

  static IndexedRecord? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String || raw['n'] is! String) return null;
    String text(String key) => raw[key] is String ? raw[key] as String : '';
    return IndexedRecord(
      id: raw['id'] as String,
      name: raw['n'] as String,
      container: raw['c'] == true,
      path: text('p'),
      note: text('t'),
      place: text('l'),
      quantity: raw['q'] is int ? raw['q'] as int : null,
      barcode: raw['b'] is String && (raw['b'] as String).isNotEmpty ? raw['b'] as String : null,
      attachments: [
        if (raw['a'] is List)
          for (final x in raw['a'] as List)
            if (x is String && x.isNotEmpty) x,
      ],
    );
  }
}

/// Kapalı bir envanterin bir bildirim satırı: gün, eşya adı ve hazır metin.
class SavedAlert {
  const SavedAlert({required this.day, required this.name, required this.line});

  final DateTime day;
  final String name;
  final String line;

  Map<String, Object?> toJson() => {'day': day.millisecondsSinceEpoch, 'name': name, 'line': line};

  static SavedAlert? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final day = raw['day'];
    final name = raw['name'];
    final line = raw['line'];
    if (day is! int || name is! String || line is! String) return null;
    return SavedAlert(day: DateTime.fromMillisecondsSinceEpoch(day), name: name, line: line);
  }
}

/// Envanterlerin listesi ve hangisinin açık olduğu, bir de envanterden
/// bağımsız kişisel ayarlar (dil, tema, ad...). Uygulama klasöründe küçük bir
/// JSON dosyasında durur; hiçbir envanterin veritabanında değil, yoksa o
/// envanter silinince ayarlar da giderdi.
///
/// İlk envanter ("main") eski kurulumun kendisidir: veritabanı ve fotoğrafları
/// eskisi gibi uygulama klasörünün kökünde durur, hiçbir şey taşınmaz. Sonra
/// eklenenler `inventories/<kimlik>/` altında.
class InventoryLibrary {
  InventoryLibrary._(this._file, this.rootDir, this.dbDir, this.activeId, this.entries, this.global, this.trashed);

  /// Uygulamanın kullandığı kütüphane; testlerde ve kütüphanesiz çalışan
  /// yerlerde null (ayarlar o zaman eskisi gibi veritabanında durur).
  static InventoryLibrary? current;

  static const mainId = 'main';
  static const _uuid = Uuid();

  final File _file;

  /// Uygulamanın belgeler klasörü (ilk envanterin fotoğrafları da burada).
  final String rootDir;

  /// Veritabanlarının klasörü (sqflite'ın varsayılanı).
  final String dbDir;

  String activeId;
  final List<InventoryEntry> entries;

  /// Silinenler: dosyaları `deleted/<kimlik>/` altında, [keepDeleted] boyunca
  /// geri getirilebilir; süresi dolan açılışta kalıcı silinir.
  final List<InventoryEntry> trashed;

  static const keepDeleted = Duration(days: 30);

  /// Kapalı envanterde arama ve QR için kapanırken yazılan dizin. Veritabanı
  /// açılmadan (aynı anda tek veritabanı açık) bakılabilsin diye ayrı dosya.
  File indexFileOf(String id) => File(p.join(rootDir, 'search', '$id.json'));

  Future<void> writeIndex(String id, List<IndexedRecord> records) async {
    final file = indexFileOf(id);
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final r in records) r.toJson()]));
    await tmp.rename(file.path);
  }

  /// Dizin (yoksa ya da bozuksa null: o envanter bir kez açılıp kapanınca olur).
  List<IndexedRecord>? readIndex(String id) {
    final file = indexFileOf(id);
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! List) return null;
      return [for (final r in raw) ?IndexedRecord.fromJson(r)];
    } on Object {
      return null;
    }
  }

  /// Envanterden bağımsız ayarlar (anahtar → değer); bkz. `AppSettings`.
  final Map<String, String> global;

  /// Yalnızca okunan kopya: hiçbir şey dosyaya yazılmaz. Kapalı envanterleri
  /// arka planda eşitleyen yalıtım kütüphaneyi böyle açar (ayarları ve
  /// envanterlerin yerini okumak için); dosyanın sahibi uygulamanın kendisidir,
  /// eski bir kopyadan yazmak onun değişikliklerini ezerdi.
  bool readOnly = false;

  static Future<InventoryLibrary> load({required String rootDir, required String dbDir, bool readOnly = false}) async {
    final file = File(p.join(rootDir, 'inventories.json'));
    Object? json;
    try {
      if (file.existsSync()) json = jsonDecode(await file.readAsString());
    } on FormatException {
      json = null; // bozuksa baştan kurulur; envanterlerin kendisi yerinde
    }
    final entries = <InventoryEntry>[
      if (json is Map && json['inventories'] is List)
        for (final raw in json['inventories'] as List) ?InventoryEntry.fromJson(raw),
    ];
    final trashed = <InventoryEntry>[
      if (json is Map && json['deleted'] is List)
        for (final raw in json['deleted'] as List) ?InventoryEntry.fromJson(raw),
    ];
    // Kütüphane dosyası kaybolsa da diskteki envanterler bulunur.
    final known = {for (final e in [...entries, ...trashed]) e.id};
    final dir = Directory(p.join(rootDir, 'inventories'));
    if (dir.existsSync()) {
      for (final sub in dir.listSync().whereType<Directory>()) {
        final id = p.basename(sub.path);
        if (!known.contains(id) && File(p.join(dbDir, 'envanter-$id.db')).existsSync()) {
          entries.add(InventoryEntry(id: id, name: '', createdAt: sub.statSync().modified));
          known.add(id);
        }
      }
    }
    if (!known.contains(mainId) && (entries.isEmpty || File(p.join(dbDir, 'envanter.db')).existsSync())) {
      entries.insert(0, InventoryEntry(id: mainId, name: '', createdAt: DateTime.now()));
    }
    final rawGlobal = json is Map ? json['global'] : null;
    final global = <String, String>{
      if (rawGlobal is Map)
        for (final e in rawGlobal.entries)
          if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
    final active = json is Map ? json['active'] : null;
    final activeId = active is String && entries.any((e) => e.id == active) ? active : entries.first.id;
    final library = InventoryLibrary._(file, rootDir, dbDir, activeId, entries, global, trashed);
    // Salt okunur kopya ne dosyayı kurar ne süresi dolanları siler.
    if (readOnly) return library..readOnly = true;
    if (!file.existsSync()) await library.save();
    await library._purgeExpired(DateTime.now());
    return library;
  }

  InventoryEntry get active => entries.firstWhere((e) => e.id == activeId);

  /// Birden çok envanter varken açık olanın adı (bildirim, widget ve yedek
  /// adlarına eklenir); tek envanterde null. [fallback]: adı boş ilk envanter.
  String? labelFor(String fallback) {
    if (entries.length < 2) return null;
    final name = active.name.trim();
    return name.isEmpty ? fallback : name;
  }

  InventoryEntry? byId(String id) => entries.where((e) => e.id == id).firstOrNull;

  /// Görünen ad; ilk envanterin adı boş olabilir ([fallback]: "Envanter").
  String nameOf(InventoryEntry e, String fallback) => e.name.trim().isEmpty ? fallback : e.name.trim();

  String dbPathOf(String id) => p.join(dbDir, id == mainId ? 'envanter.db' : 'envanter-$id.db');

  String docsOf(String id) => id == mainId ? rootDir : p.join(rootDir, 'inventories', id);

  /// Yazım yarıda kalırsa eski dosya bozulmasın: önce geçici dosya, sonra ad değişimi.
  /// Yazımlar sırayla: aynı anda iki yazım aynı geçici dosyayı kullanıp eskiyi
  /// kalıcı yapabiliyordu (ör. envanter geçişi ile bir ayar yazımı üst üste).
  /// Her yazım sırası gelince o anki durumu yazar.
  Future<void> _saving = Future.value();

  Future<void> save() {
    if (readOnly) return Future.value();
    final run = _saving.then((_) => _write());
    _saving = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> _write() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'active': activeId,
      'inventories': [for (final e in entries) e.toJson()],
      if (trashed.isNotEmpty) 'deleted': [for (final e in trashed) e.toJson()],
      'global': global,
    }));
    await tmp.rename(_file.path);
  }

  Future<void> writeGlobals(Map<String, String> values) async {
    var changed = false;
    values.forEach((k, v) {
      if (global[k] != v) {
        global[k] = v;
        changed = true;
      }
    });
    if (changed) await save();
  }

  /// Boş bir envanter kaydı açar (veritabanı ilk açılışta kurulur).
  Future<InventoryEntry> create(String name) async {
    final entry = InventoryEntry(id: _uuid.v4(), name: name.trim(), createdAt: DateTime.now());
    Directory(docsOf(entry.id)).createSync(recursive: true);
    entries.add(entry);
    await save();
    return entry;
  }

  Future<void> update(InventoryEntry entry) async {
    final i = entries.indexWhere((e) => e.id == entry.id);
    if (i < 0) return;
    entries[i] = entry;
    await save();
  }

  Future<void> setActive(String id) async {
    final entry = byId(id);
    if (entry == null) return;
    activeId = id;
    await update(entry.copyWith(openedAt: DateTime.now()));
  }

  String _deletedDir(String id) => p.join(rootDir, 'deleted', id);

  static const _dbSuffixes = ['', '-journal', '-wal', '-shm'];

  /// Envanteri Silinenler'e taşır: veritabanı ve fotoğrafları `deleted/<kimlik>/`
  /// altına, [keepDeleted] boyunca geri getirilebilir. Açık olan taşınamaz
  /// (önce başka birine geçilmeli). İlk envanterin fotoğrafları kökteki
  /// `images/` klasöründe: [keep] (kişisel fotoğraf) yerinde kalır.
  Future<bool> delete(String id, {Set<String> keep = const {}, DateTime? now}) async {
    final entry = byId(id);
    if (id == activeId || entry == null) return false;
    final dest = _deletedDir(id);
    Directory(p.join(dest, 'db')).createSync(recursive: true);
    for (final suffix in _dbSuffixes) {
      final f = File('${dbPathOf(id)}$suffix');
      if (f.existsSync()) f.renameSync(p.join(dest, 'db', '${p.basename(dbPathOf(id))}$suffix'));
    }
    if (id == mainId) {
      final images = Directory(p.join(rootDir, 'images'));
      final target = Directory(p.join(dest, 'files', 'images'))..createSync(recursive: true);
      if (images.existsSync()) {
        for (final f in images.listSync().whereType<File>()) {
          if (!keep.contains(p.relative(f.path, from: rootDir))) f.renameSync(p.join(target.path, p.basename(f.path)));
        }
      }
      final files = Directory(p.join(rootDir, 'files'));
      final targetFiles = Directory(p.join(dest, 'files', 'files'))..createSync(recursive: true);
      if (files.existsSync()) {
        for (final f in files.listSync().whereType<File>()) {
          if (!keep.contains(p.relative(f.path, from: rootDir))) f.renameSync(p.join(targetFiles.path, p.basename(f.path)));
        }
      }
    } else {
      final dir = Directory(docsOf(id));
      if (dir.existsSync()) dir.renameSync(p.join(dest, 'files'));
    }
    entries.removeWhere((e) => e.id == id);
    trashed.add(entry.copyWith(deletedAt: now ?? DateTime.now()));
    await save();
    return true;
  }

  /// Silinenler'den geri getirir: dosyalar yerine döner, envanter listede.
  Future<bool> restore(String id) async {
    final entry = trashed.where((e) => e.id == id).firstOrNull;
    if (entry == null) return false;
    final src = _deletedDir(id);
    final dbDirSrc = Directory(p.join(src, 'db'));
    if (dbDirSrc.existsSync()) {
      for (final f in dbDirSrc.listSync().whereType<File>()) {
        f.renameSync(p.join(dbDir, p.basename(f.path)));
      }
    }
    final files = Directory(p.join(src, 'files'));
    if (id == mainId) {
      final images = Directory(p.join(rootDir, 'images'))..createSync(recursive: true);
      final saved = Directory(p.join(files.path, 'images'));
      if (saved.existsSync()) {
        for (final f in saved.listSync().whereType<File>()) {
          f.renameSync(p.join(images.path, p.basename(f.path)));
        }
      }
      final destFiles = Directory(p.join(rootDir, 'files'))..createSync(recursive: true);
      final savedFiles = Directory(p.join(files.path, 'files'));
      if (savedFiles.existsSync()) {
        for (final f in savedFiles.listSync().whereType<File>()) {
          f.renameSync(p.join(destFiles.path, p.basename(f.path)));
        }
      }
    } else if (files.existsSync()) {
      Directory(p.dirname(docsOf(id))).createSync(recursive: true);
      files.renameSync(docsOf(id));
    } else {
      Directory(docsOf(id)).createSync(recursive: true);
    }
    Directory(src).deleteSync(recursive: true);
    trashed.removeWhere((e) => e.id == id);
    entries.add(entry.copyWith(clearDeleted: true));
    await save();
    return true;
  }

  /// Silinenler'deki envanteri kalıcı siler (geri getirilemez).
  Future<void> purge(String id) async {
    final dir = Directory(_deletedDir(id));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    final index = indexFileOf(id);
    if (index.existsSync()) index.deleteSync();
    trashed.removeWhere((e) => e.id == id);
    await save();
  }

  /// Açılışta: süresi dolan silinenler kalıcı gider.
  Future<void> _purgeExpired(DateTime now) async {
    final expired = [
      for (final e in trashed)
        if (e.deletedAt == null || now.difference(e.deletedAt!) > keepDeleted) e.id,
    ];
    for (final id in expired) {
      await purge(id);
    }
  }

  /// Açılamayan veritabanını kenara alır: Silinenler'e ayrı bir envanter
  /// olarak girer ("… (açılamadı)"), envanter boş bir veritabanıyla sürer.
  /// Fotoğraflar asıl envanterde kalır. Geri getirilirse yeniden denenir.
  Future<InventoryEntry> quarantineDatabase(String id, String name) async {
    final copy = InventoryEntry(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
      deletedAt: DateTime.now(),
    );
    final dest = Directory(p.join(_deletedDir(copy.id), 'db'))..createSync(recursive: true);
    for (final suffix in _dbSuffixes) {
      final f = File('${dbPathOf(id)}$suffix');
      if (f.existsSync()) f.renameSync(p.join(dest.path, '${p.basename(dbPathOf(copy.id))}$suffix'));
    }
    trashed.add(copy);
    await save();
    return copy;
  }
}
