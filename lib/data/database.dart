import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'node.dart';

/// Tek tablo + küçük bir anahtar/değer tablosu. Agac yapisi `parent_id`
/// üzerinden kurulur, silme islemi `deleted_at` ile yumuşak yapilir.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;
  Database get db {
    final d = _db;
    if (d == null) throw StateError('Veritabani acilmadi');
    return d;
  }

  Future<void> open() async {
    if (_db != null) return;
    final dir = await getDatabasesPath();
    _db = await _openAt(p.join(dir, 'envanter.db'));
  }

  /// Başka bir envantere geçerken: açık olan kapanır, [path]'teki açılır
  /// (yoksa boş olarak kurulur).
  Future<void> openAt(String path) async {
    await close();
    _db = await _openAt(path);
  }

  /// Testler bellek ici bir kopyayla calissin diye.
  @visibleForTesting
  Future<void> openForTest({bool inMemory = true, String? path}) async {
    await close();
    _db = await _openAt(inMemory ? inMemoryDatabasePath : path!);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _openAt(String path) => openDatabaseAt(path);

  static Future<Database> openDatabaseAt(String path) {
    return openDatabase(
      path,
      version: 23,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE nodes (
            id TEXT PRIMARY KEY,
            parent_id TEXT REFERENCES nodes(id) ON DELETE CASCADE,
            kind TEXT NOT NULL,
            name TEXT NOT NULL DEFAULT '',
            image_path TEXT,
            color INTEGER NOT NULL,
            lat REAL,
            lng REAL,
            location_label TEXT,
            note TEXT,
            image_sig TEXT,
            updated_by TEXT,
            sort_index REAL NOT NULL DEFAULT 0,
            in_drawer INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            lost_at INTEGER,
            lost_from TEXT,
            icon TEXT,
            managers TEXT,
            quantity INTEGER,
            is_full INTEGER NOT NULL DEFAULT 0,
            held_by TEXT,
            purchased_at INTEGER,
            expires_at INTEGER,
            shelf_life TEXT,
            warranty_ends_at INTEGER,
            warranty TEXT,
            expiry_warn TEXT,
            min_quantity INTEGER,
            field_times TEXT,
            wanted_at INTEGER,
            auto_shop INTEGER NOT NULL DEFAULT 0,
            lots TEXT,
            buying_by TEXT,
            buying_at INTEGER,
            bought_at INTEGER,
            attachments TEXT,
            barcode TEXT,
            unit TEXT,
            borrowed_to TEXT,
            borrowed_at INTEGER,
            return_due_at INTEGER,
            price TEXT,
            serial TEXT,
            service_every TEXT,
            service_task TEXT,
            serviced_at INTEGER,
            service_log TEXT
          )
        ''');
        await d.execute('CREATE INDEX idx_nodes_parent ON nodes(parent_id)');
        await d.execute('CREATE INDEX idx_nodes_deleted ON nodes(deleted_at)');
        await d.execute('CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)');
        await d.execute(_purgedTable);
      },
      onUpgrade: (d, from, to) async {
        // 2: ilk görüntüyle arama denemesi (dHash + histogram). Gerçek
        //    fotoğraflarda ayırt edemediği için 3'te bırakıldı; sütunları
        //    eski kurulumlarda kalıyor ama kullanılmıyor.
        if (from < 2) {
          await d.execute('ALTER TABLE nodes ADD COLUMN image_hash TEXT');
          await d.execute('ALTER TABLE nodes ADD COLUMN image_hist TEXT');
        }
        // 3: pencere aramalı renk düzeni parmak izi.
        if (from < 3) {
          await d.execute('ALTER TABLE nodes ADD COLUMN image_sig TEXT');
        }
        // 4: ortak kullanım için kalıcı silme izleri.
        if (from < 4) {
          await d.execute(_purgedTable);
        }
        // 5: son değiştiren cihaz ("Ayşe taşıdı").
        if (from < 5) {
          await d.execute('ALTER TABLE nodes ADD COLUMN updated_by TEXT');
        }
        // 6: kayıp çekmecesi.
        if (from < 6) {
          await d.execute('ALTER TABLE nodes ADD COLUMN lost_at INTEGER');
          await d.execute('ALTER TABLE nodes ADD COLUMN lost_from TEXT');
        }
        // 7: kartın seçilebilir simgesi ve klasör sorumluları.
        if (from < 7) {
          await d.execute('ALTER TABLE nodes ADD COLUMN icon TEXT');
          await d.execute('ALTER TABLE nodes ADD COLUMN managers TEXT');
        }
        // 8: eşya adedi (sarf malzemesi).
        if (from < 8) {
          await d.execute('ALTER TABLE nodes ADD COLUMN quantity INTEGER');
        }
        // 9: klasörün "dolu" işareti (yer ararken görünsün).
        if (from < 9) {
          await d.execute('ALTER TABLE nodes ADD COLUMN is_full INTEGER NOT NULL DEFAULT 0');
        }
        // 11: ortak kaydı kendi özel alanına alan cihaz ("Ayşe'de").
        if (from < 11) {
          await d.execute('ALTER TABLE nodes ADD COLUMN held_by TEXT');
        }
        // 12: satın alma, son kullanma, garanti ve eşyaya özel uyarı süresi.
        if (from < 12) {
          for (final column in [
            'purchased_at INTEGER',
            'expires_at INTEGER',
            'shelf_life TEXT',
            'warranty_ends_at INTEGER',
            'warranty TEXT',
            'expiry_warn TEXT',
          ]) {
            await d.execute('ALTER TABLE nodes ADD COLUMN $column');
          }
        }
        // 13: "en az adet" ve alan bazında birleştirme için grup zamanları.
        if (from < 13) {
          await d.execute('ALTER TABLE nodes ADD COLUMN min_quantity INTEGER');
          await d.execute('ALTER TABLE nodes ADD COLUMN field_times TEXT');
        }
        // 14: alışveriş listesinde (elle eklenen).
        if (from < 14) {
          await d.execute('ALTER TABLE nodes ADD COLUMN wanted_at INTEGER');
        }
        // 15: eşya bitince/azalınca/tarihi geçince listeye kendiliğinden girsin mi.
        if (from < 15) {
          await d.execute('ALTER TABLE nodes ADD COLUMN auto_shop INTEGER NOT NULL DEFAULT 0');
        }
        // 16: farklı son kullanma tarihli paketler.
        if (from < 16) {
          await d.execute('ALTER TABLE nodes ADD COLUMN lots TEXT');
        }
        // 17: "alıyorum" işareti ve markette işaretlenip yerleştirilmeyi bekleyenler.
        if (from < 17) {
          await d.execute('ALTER TABLE nodes ADD COLUMN buying_by TEXT');
          await d.execute('ALTER TABLE nodes ADD COLUMN buying_at INTEGER');
          await d.execute('ALTER TABLE nodes ADD COLUMN bought_at INTEGER');
        }
        // 18: ekler (belge, fotoğraf, video, bağlantı).
        if (from < 18) {
          await d.execute('ALTER TABLE nodes ADD COLUMN attachments TEXT');
        }
        // 19: ürün barkodu (okutunca kayıt bulunur).
        if (from < 19) {
          await d.execute('ALTER TABLE nodes ADD COLUMN barcode TEXT');
        }
        // 20: miktar ölçü birimi (kg, adet, metre vb.).
        if (from < 20) {
          await d.execute('ALTER TABLE nodes ADD COLUMN unit TEXT');
        }
        // 21: emanet / ödünç takibi (kime verildi, ne zaman, iade tarihi).
        if (from < 21) {
          await d.execute('ALTER TABLE nodes ADD COLUMN borrowed_to TEXT');
          await d.execute('ALTER TABLE nodes ADD COLUMN borrowed_at INTEGER');
          await d.execute('ALTER TABLE nodes ADD COLUMN return_due_at INTEGER');
        }
        // 22: değer (fiyat + para birimi, tek metin) ve seri/model numarası.
        if (from < 22) {
          await d.execute('ALTER TABLE nodes ADD COLUMN price TEXT');
          await d.execute('ALTER TABLE nodes ADD COLUMN serial TEXT');
        }
        // 23: periyodik bakım (aralık, ne yapılacağı, son bakım günü, geçmiş).
        if (from < 23) {
          await d.execute('ALTER TABLE nodes ADD COLUMN service_every TEXT');
          await d.execute('ALTER TABLE nodes ADD COLUMN service_task TEXT');
          await d.execute('ALTER TABLE nodes ADD COLUMN serviced_at INTEGER');
          await d.execute('ALTER TABLE nodes ADD COLUMN service_log TEXT');
        }
      },
    );
  }

  /// Kalıcı silinen kayıtların izi. Dosyayla paylaşımda karşı tarafın eski
  /// kopyası bu kaydı geri getirmesin diye tutulur.
  static const _purgedTable =
      'CREATE TABLE purged (id TEXT PRIMARY KEY, purged_at INTEGER NOT NULL)';

  Future<Map<String, int>> loadTombstones() async {
    final rows = await db.query('purged');
    return {for (final r in rows) r['id']! as String: r['purged_at']! as int};
  }

  /// Birleştirmenin sonucunu tek bir işlemde yazar: ya hepsi ya hiçbiri.
  Future<void> applySync({
    required Iterable<Node> upserts,
    required Iterable<String> removals,
    required Map<String, int> tombstones,
    required Iterable<String> clearedTombstones,
  }) async {
    final batch = db.batch();
    _deferForeignKeys(batch);
    for (final n in upserts) {
      _put(batch, n);
    }
    for (final id in removals) {
      batch.delete('nodes', where: 'id = ?', whereArgs: [id]);
    }
    tombstones.forEach((id, at) {
      batch.insert('purged', {'id': id, 'purged_at': at},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
    for (final id in clearedTombstones) {
      batch.delete('purged', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Node>> loadAll() async {
    final rows = await db.query('nodes');
    return rows.map(Node.fromMap).toList(growable: false);
  }

  Future<void> upsert(Node n) => upsertAll([n]);

  Future<void> upsertAll(Iterable<Node> nodes) async {
    final batch = db.batch();
    _deferForeignKeys(batch);
    for (final n in nodes) {
      _put(batch, n);
    }
    await batch.commit(noResult: true);
  }

  /// Var olan satırı günceller, yoksa ekler. "INSERT OR REPLACE" olmaz:
  /// SQLite onu sil + ekle olarak yapar ve ON DELETE CASCADE yüzünden
  /// klasörün içindekiler de silinirdi. (UPSERT sözdizimi eski Android
  /// sürümlerindeki SQLite'ta yok.)
  static void _put(Batch batch, Node n) {
    final row = n.toMap();
    batch.update('nodes', {...row}..remove('id'), where: 'id = ?', whereArgs: [n.id]);
    batch.insert('nodes', row, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Aynı toplu yazımda üst kayıt alt kayıttan sonra gelebilir (ör. yeni
  /// bir kutu ve içindekiler); bütünlük işlem sonunda denetlenir.
  static void _deferForeignKeys(Batch batch) => batch.execute('PRAGMA defer_foreign_keys = ON');

  /// Başka bir envanterin (kapalı) veritabanına kayıt yazar: envanterler arası aktarma. [_put] kuralıyla,
  /// tek işlemde; gelen kimliklerin oradaki silme izleri de kalkar (taşınıp geri gelen kayıt, ilk taşımanın
  /// bıraktığı izle silinmesin).
  static Future<void> writeInto(Database db, Iterable<Node> nodes) async {
    final batch = db.batch();
    _deferForeignKeys(batch);
    for (final n in nodes) {
      _put(batch, n);
      batch.delete('purged', where: 'id = ?', whereArgs: [n.id]);
    }
    await batch.commit(noResult: true);
  }

  /// Kalıcı silme; her kayıt için iz bırakır (bkz. [loadTombstones]).
  Future<void> hardDelete(Iterable<String> ids, {required DateTime at}) async {
    final batch = db.batch();
    for (final id in ids) {
      batch.delete('nodes', where: 'id = ?', whereArgs: [id]);
      batch.insert('purged', {'id': id, 'purged_at': at.millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<String?> readMeta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> writeMeta(String key, String value) async {
    await db.insert('meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
