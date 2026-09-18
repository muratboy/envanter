import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../core/app_paths.dart';
import '../core/text_match.dart';
import '../data/library.dart';
import '../data/node.dart';
import '../state/inventory_store.dart';
import '../sync/wire.dart';

/// İçe aktarma neden olmadı.
enum BackupProblem {
  /// Dosya açılamadı ya da içeriği bozuk.
  unreadable,

  /// Başka bir uygulamanın (ya da başka bir şeyin) dosyası.
  notOurs,

  /// Uygulamanın daha yeni bir sürümünden.
  newerVersion,
}

class BackupException implements Exception {
  const BackupException(this.problem);
  final BackupProblem problem;

  @override
  String toString() => 'BackupException(${problem.name})';
}

/// İçe aktarmanın sonucu.
class BackupImport {
  const BackupImport({
    required this.added,
    required this.updated,
    required this.photos,
    required this.skipped,
    this.files = 0,
  });

  /// Bu cihazda olmayan, eklenen kayıtlar.
  final int added;

  /// Zaten vardı, dosyadaki daha yeniydi.
  final int updated;

  /// Kopyalanan fotoğraf sayısı.
  final int photos;

  /// Kopyalanan ek dosyası (belge, video...) sayısı.
  final int files;

  /// Bozuk olduğu için atlanan kayıtlar.
  final int skipped;

  int get total => added + updated;
}

/// Envanterin tek dosyalık yedeği.
///
///     envanter.json      kayıtlar + kalıcı silme izleri
///     images/<ad>.jpg    kayıtların kullandığı fotoğraflar
///     files/<ad>.<uz>    kayıtların ekleri (belge, fotoğraf, video)
///
/// İçe aktarma birleştirmedir: aynı kaydın iki sürümü varsa daha yeni
/// düzenlenmiş olan kalır (ortak kullanımdaki kuralın aynısı). Böylece hem
/// yeni kurulan bir uygulamaya taşıma, hem de başka bir cihazın yedeğini
/// üstüne ekleme aynı yolla çalışır.
class BackupService {
  static const dataEntry = 'envanter.json';
  static const _app = 'envanter';

  /// Bugünkü biçim. İleride değişirse eski dosyalar yine okunabilir.
  static const version = 1;

  /// Yedeği [into] klasörüne yazar ve dosyayı döner.
  /// Yedek dosyasının adının tarihten önceki kısmı. İlk envanterde eskisi gibi
  /// "envanter-"; ötekilerde adı ve kendine özgü bir ekle ("envanter-atolye-kqzmab-",
  /// bkz. [fileLabelFor]), aynı klasöre yazılan yedekler karışmasın ve eskileri silinirken
  /// birbirininki silinmesin. Etikete rakam girmez: yerel taraf adı tarihin ilk rakamına
  /// kadar okur.
  static String fileLabel() {
    final library = InventoryLibrary.current;
    if (library == null || library.activeId == InventoryLibrary.mainId) return 'envanter-';
    return fileLabelFor(id: library.activeId, name: library.active.name);
  }

  /// İlk envanter dışındakilerin etiketi: adın harfleri + envanterin kimliğinden türeyen
  /// altı harf. Yalnızca ada bakılırken "Depo 1" ile "Depo 2" (ya da Latin harfi olmayan iki
  /// ad) aynı etiketi alıyor, yerel taraf "en yeni dört yedeği" ikisi için ortak saydığından
  /// sık değişen envanter ötekinin bütün yedeklerini sildiriyordu.
  static String fileLabelFor({required String id, required String name}) {
    final slug = foldForSearch(name).replaceAll(RegExp('[^a-z]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    // Kimliğin kısa özeti (FNV-1a), rakamsız: String.hashCode sürümden sürüme değişebilir,
    // etiket ise aynı envanter için hep aynı kalmalı.
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    final tag = StringBuffer();
    for (var i = 0; i < 6; i++) {
      tag.writeCharCode(0x61 + hash % 26);
      hash ~/= 26;
    }
    return 'envanter-${slug.isEmpty ? 'envanter' : slug}-$tag-';
  }

  /// [onProgress]: 0–1 arası ilerleme (yazılan bayta göre); büyük eklerde uzun sürer.
  static Future<File> export(
    InventoryStore store, {
    required Directory into,
    void Function(double progress)? onProgress,
  }) async {
    // Yedek kullanıcının kendisi: yalnızca bende tutulanlar da girer.
    final snapshot = store.fullSnapshot();

    final data = <String, Object?>{
      'app': _app,
      'v': version,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'nodes': [for (final n in snapshot.nodes.values) n.toMap()],
      'tombstones': snapshot.tombstones,
      // Geri yüklenince özel kayıtlar özel kalsın, ortak kullanıma sızmasın.
      'private': store.settings.privateIds,
    };
    // Yalnızca kayıtların kullandığı fotoğraflar ve ekler; profil resmi gibi
    // başka dosyalar yedeğe girmez. (zip içindeki ad, diskteki yol)
    final entries = <(String, String)>[];
    final seen = <String>{};
    for (final node in snapshot.nodes.values) {
      for (final rel in [
        if (node.imagePath case final img? when isSafeImagePath(img)) img,
        for (final a in node.attachments)
          if (a.file case final f? when isSafeFilePath(f)) f,
      ]) {
        if (!seen.add(rel)) continue;
        final file = AppPaths.imageFile(rel);
        if (file != null) entries.add((rel, file.path));
      }
    }

    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(':', '')
        .replaceAll('T', '-');
    final out = File(p.join(into.path, '${fileLabel()}$stamp.zip'));
    await out.parent.create(recursive: true);
    // Ayrı yalıtımda: kayıtların metne çevrilmesi ve video gibi büyük eklerin
    // yazılması sürerken arayüz donmasın.
    await _inBackground(_writeZip, (out.path, data, entries), onProgress);
    return out;
  }

  /// İşi ayrı yalıtımda çalıştırır; yalıtım ilerlemeyi (0–1) kapıdan bildirir.
  static Future<R> _inBackground<A, R>(
    R Function(A args, SendPort? progress) job,
    A args,
    void Function(double progress)? onProgress,
  ) async {
    if (onProgress == null) return _run(job, args, null);
    final port = ReceivePort();
    port.listen((message) {
      if (message is double) onProgress(message);
    });
    try {
      return await _run(job, args, port.sendPort);
    } finally {
      port.close();
    }
  }

  /// Yalıtıma giden kapanış burada kurulur: kapsamında yalnızca gönderilebilir
  /// şeyler olsun ([_inBackground]'daki `onProgress` arayüzden gelen bir
  /// kapanış; aynı kapsamda kurulsaydı o da yalıtıma gönderilmeye çalışılırdı).
  static Future<R> _run<A, R>(R Function(A args, SendPort? progress) job, A args, SendPort? progress) =>
      Isolate.run(() => job(args, progress));

  /// Zip doğrudan diske, dosya dosya yazılır: yedeğin tamamı belleğe alınsaydı
  /// birkaç videoluk bir envanter telefonun belleğini aşardı.
  static void _writeZip((String, Map<String, Object?>, List<(String, String)>) args, SendPort? progress) {
    final (path, data, entries) = args;
    final sizes = [for (final (_, source) in entries) File(source).lengthSync()];
    final total = sizes.fold<int>(0, (a, b) => a + b);
    final encoder = ZipFileEncoder()..create(path);
    encoder.addArchiveFile(ArchiveFile.bytes(dataEntry, utf8.encode(jsonEncode(data))));
    var written = 0;
    for (final (i, (name, source)) in entries.indexed) {
      // Fotoğraf ve video zaten sıkışık; yeniden sıkıştırmak yalnızca zaman alır.
      encoder.addArchiveFile(
        ArchiveFile.stream(name, InputFileStream(source))..compression = CompressionType.none,
      );
      written += sizes[i];
      if (total > 0) progress?.send(written / total);
    }
    encoder.closeSync();
    progress?.send(1.0);
  }

  /// [file] içindeki envanteri bu cihazdakiyle birleştirir. Dosyanın açılması,
  /// kayıtların doğrulanması ve fotoğrafların/eklerin diske yazılması ayrı
  /// yalıtımda: video ekli büyük bir yedekte arayüz donuyordu. [onProgress] 0–1.
  static Future<BackupImport> import(
    File file,
    InventoryStore store, {
    void Function(double progress)? onProgress,
  }) async {
    final unpacked = await _inBackground(_unpack, (file.path, AppPaths.docsDir), onProgress);
    // Yeni yazılan dosyalar için "yok" diye önbelleklenmiş cevaplar düşsün.
    for (final rel in unpacked.written) {
      AppPaths.forget(rel);
    }
    final stats = await store.importBackup(
      nodes: unpacked.nodes,
      tombstones: unpacked.tombstones,
      privateIds: unpacked.privateIds,
    );
    return BackupImport(
      added: stats.added,
      updated: stats.updated,
      photos: unpacked.photos,
      files: unpacked.files,
      skipped: unpacked.skipped,
    );
  }

  /// Yedeği açar (yalıtımda çalışır): kayıtları okur ve doğrular, bu cihazda
  /// olmayan fotoğraf ve ekleri [docsDir] altına yazar.
  static _Unpacked _unpack((String, String) args, SendPort? progress) {
    final (zipPath, docsDir) = args;
    final Archive archive;
    final input = InputFileStream(zipPath);
    try {
      // Dosyadan akışla: yalnızca istenen girdiler okunur.
      archive = ZipDecoder().decodeStream(input);
    } on Object {
      input.closeSync();
      throw const BackupException(BackupProblem.unreadable);
    }
    try {
      return _unpackFrom(archive, docsDir, progress);
    } finally {
      input.closeSync();
    }
  }

  static _Unpacked _unpackFrom(Archive archive, String docsDir, SendPort? progress) {
    final entry = archive.findFile(dataEntry);
    if (entry == null) throw const BackupException(BackupProblem.notOurs);

    final Object? raw;
    try {
      raw = jsonDecode(utf8.decode(entry.readBytes() ?? const []));
    } on FormatException {
      throw const BackupException(BackupProblem.unreadable);
    }
    if (raw is! Map || raw['app'] != _app) throw const BackupException(BackupProblem.notOurs);
    final v = raw['v'];
    if (v is! int || v > version) throw const BackupException(BackupProblem.newerVersion);

    final rawNodes = raw['nodes'];
    if (rawNodes is! List) throw const BackupException(BackupProblem.unreadable);
    final nodes = <String, Node>{};
    var skipped = 0;
    for (final item in rawNodes) {
      // Ağdan gelen veriyle aynı süzgeç: bozuk alanlar ve güvensiz dosya
      // yolları içeri alınmaz.
      final node = sanitizeNode(item);
      if (node == null) {
        skipped++;
        continue;
      }
      nodes[node.id] = node;
    }

    final rawTombstones = raw['tombstones'];
    final tombstones = <String, int>{
      if (rawTombstones is Map)
        for (final e in rawTombstones.entries)
          if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt(),
    };

    // Fotoğraflar önce: kayıtlar göründüğü an kartlarında dursunlar.
    final wanted = {
      for (final n in nodes.values) ...[
        if (n.imagePath case final rel? when isSafeImagePath(rel)) rel,
        for (final a in n.attachments) ?a.file,
      ],
    };
    // Bu cihazda zaten olanlar yeniden yazılmaz.
    final todo = [
      for (final item in archive.files)
        if (item.isFile && wanted.contains(item.name) && !File(p.join(docsDir, item.name)).existsSync()) item,
    ];
    final total = todo.fold<int>(0, (a, item) => a + item.size);
    var done = 0;
    var photos = 0;
    var files = 0;
    final written = <String>[];
    for (final item in todo) {
      final out = File(p.join(docsDir, item.name));
      out.parent.createSync(recursive: true);
      // Önce yanına (.part), bitince yerine. Doğrudan son yoluna yazılırken yarıda kesilen
      // aktarma (yer bitti, uygulama kapandı) orada yarım dosya bırakıyor, sonraki denemede
      // "zaten var" diye atlandığı için fotoğraf ya da ek hep bozuk kalıyordu.
      final part = File('${out.path}.part');
      try {
        // Belleğe almadan diske: ek bir video olabilir.
        final sink = OutputFileStream(part.path);
        try {
          item.writeContent(sink);
        } finally {
          sink.closeSync();
        }
        part.renameSync(out.path);
      } on Object {
        // Yarım parça yer tutmasın; hata olduğu gibi yukarı gider.
        try {
          if (part.existsSync()) part.deleteSync();
        } on FileSystemException {
          // Silinemezse açılışta süpürülür ([InventoryStore._sweepPartials]).
        }
        rethrow;
      }
      written.add(item.name);
      isSafeFilePath(item.name) ? files++ : photos++;
      done += item.size;
      if (total > 0) progress?.send(done / total);
    }
    progress?.send(1.0);

    final rawPrivate = raw['private'];
    return _Unpacked(
      nodes: nodes,
      tombstones: tombstones,
      privateIds: [
        if (rawPrivate is List)
          for (final id in rawPrivate)
            if (id is String && id.isNotEmpty) id,
      ],
      photos: photos,
      files: files,
      skipped: skipped,
      written: written,
    );
  }
}

/// Yedekten okunanlar (yalıtımdan ana tarafa döner).
class _Unpacked {
  const _Unpacked({
    required this.nodes,
    required this.tombstones,
    required this.privateIds,
    required this.photos,
    required this.files,
    required this.skipped,
    required this.written,
  });

  final Map<String, Node> nodes;
  final Map<String, int> tombstones;
  final List<String> privateIds;
  final int photos;
  final int files;
  final int skipped;

  /// Diske yeni yazılan dosyaların göreli yolları.
  final List<String> written;
}
