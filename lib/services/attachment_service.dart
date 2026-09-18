import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/app_paths.dart';
import '../data/node.dart';
import 'platform_bridge.dart';

/// Ek seçmenin sonucu: eklenenler ve neden eklenemeyenler.
class AttachmentPick {
  const AttachmentPick({this.added = const [], this.tooLarge = const [], this.failed = 0});

  final List<Attachment> added;

  /// Sınırı ([Attachment.maxBytes]) aşan dosyaların adları.
  final List<String> tooLarge;

  /// Okunamayan dosya sayısı.
  final int failed;

  bool get isEmpty => added.isEmpty && tooLarge.isEmpty && failed == 0;
}

/// Kayıtlara iliştirilen dosyalar: seçilir, envanterin `files/` klasörüne
/// alınır. Kopya şart: galerideki ya da İndirilenler'deki özgün dosya silinse
/// de ek durur, ortak kullanımda karşıya gider, yedeğe girer.
class AttachmentService {
  static final _picker = ImagePicker();
  static const _uuid = Uuid();

  /// Belgenin fotoğrafı okunabilsin diye kart fotoğrafından büyük tutulur.
  static const double _photoEdge = 2600;
  static const int _photoQuality = 90;

  static const _mimes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'mp4': 'video/mp4',
    'm4v': 'video/mp4',
    'mov': 'video/quicktime',
    '3gp': 'video/3gpp',
    'mkv': 'video/x-matroska',
    'webm': 'video/webm',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
  };

  static String? mimeOf(String path) => _mimes[p.extension(path).replaceFirst('.', '').toLowerCase()];

  static String newId() => _uuid.v4().substring(0, 13);

  /// Kamerayla fotoğraf.
  static Future<AttachmentPick> takePhoto(String name) async {
    if (!await PlatformBridge.ensureCamera()) return const AttachmentPick();
    final shot = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: _photoEdge,
      maxHeight: _photoEdge,
      imageQuality: _photoQuality,
    );
    return _adopt([?shot], photo: name, video: name);
  }

  /// Kamerayla video.
  static Future<AttachmentPick> recordVideo(String name) async {
    if (!await PlatformBridge.ensureCamera()) return const AttachmentPick();
    final clip = await _picker.pickVideo(source: ImageSource.camera);
    return _adopt([?clip], photo: name, video: name);
  }

  /// Galeriden fotoğraf ve video (birden çok seçilebilir).
  static Future<AttachmentPick> fromGallery({required String photo, required String video}) async {
    final picked = await _picker.pickMultipleMedia(
      maxWidth: _photoEdge,
      maxHeight: _photoEdge,
      imageQuality: _photoQuality,
    );
    return _adopt(picked, photo: photo, video: video);
  }

  /// Telefondaki herhangi bir dosya (PDF kılavuz, fatura...).
  static Future<AttachmentPick> documents() async {
    final dir = p.join(AppPaths.docsDir, 'files');
    final picked = await PlatformBridge.pickDocuments(dir, max: Attachment.maxBytes);
    final added = <Attachment>[];
    final tooLarge = <String>[];
    var failed = 0;
    final now = DateTime.now();
    for (final d in picked) {
      final file = d.file;
      if (d.tooLarge) {
        tooLarge.add(d.name);
      } else if (file == null || !Attachment.isSafeFile('files/$file')) {
        failed++;
      } else {
        AppPaths.forget('files/$file');
        added.add(Attachment(
          id: newId(),
          // Uzantı satırın altında ayrıca yazıyor; adda tekrar etmesin.
          name: _title(p.basenameWithoutExtension(d.name), d.name),
          addedAt: _nth(now, added.length),
          file: 'files/$file',
          mime: d.mime ?? mimeOf(file),
          size: d.size,
        ));
      }
    }
    return AttachmentPick(added: added, tooLarge: tooLarge, failed: failed);
  }

  /// Birlikte seçilenler seçildikleri sırada kalsın: ekler eklenme anına göre
  /// dizilir (bkz. [Attachment.order]); aynı milisaniyede eklenenlerin sırası
  /// kimliğe, yani rastgele bir şeye kalırdı.
  static DateTime _nth(DateTime base, int index) => base.add(Duration(milliseconds: index));

  static String _title(String name, String fallback) {
    final t = name.trim();
    final title = t.isEmpty ? fallback.trim() : t;
    return title.length > 120 ? title.substring(0, 120) : title;
  }

  /// image_picker'ın önbelleğe koyduğu dosyaları `files/` altına taşır.
  static Future<AttachmentPick> _adopt(List<XFile> picked, {required String photo, required String video}) async {
    final added = <Attachment>[];
    final tooLarge = <String>[];
    var failed = 0;
    final now = DateTime.now();
    for (final x in picked) {
      final source = File(x.path);
      try {
        final ext = p.extension(x.path).toLowerCase().replaceAll(RegExp('[^a-z0-9.]'), '');
        final mime = x.mimeType ?? mimeOf(x.path) ?? 'application/octet-stream';
        final isVideo = mime.startsWith('video/');
        final size = await source.length();
        if (size > Attachment.maxBytes) {
          tooLarge.add(isVideo ? video : photo);
          await source.delete();
          continue;
        }
        final rel = 'files/${_uuid.v4()}${ext.length < 2 || ext.length > 9 ? (isVideo ? '.mp4' : '.jpg') : ext}';
        final target = File(AppPaths.abs(rel));
        await target.parent.create(recursive: true);
        try {
          // Aynı diskte: video baştan kopyalanmaz, yalnızca yeri değişir.
          await source.rename(target.path);
        } on FileSystemException {
          await source.copy(target.path);
          await source.delete();
        }
        AppPaths.forget(rel);
        added.add(Attachment(
          id: newId(),
          name: isVideo ? video : photo,
          addedAt: _nth(now, added.length),
          file: rel,
          mime: mime,
          size: size,
        ));
      } on FileSystemException {
        failed++;
      }
    }
    return AttachmentPick(added: added, tooLarge: tooLarge, failed: failed);
  }

  /// Yazılan adresten bağlantı; "youtube.com/…" gibi şemasız yazılana https eklenir.
  /// Adres geçersizse null.
  static Attachment? link(String address, String title) {
    var url = address.trim();
    if (url.isEmpty) return null;
    if (!url.contains('://')) url = 'https://$url';
    if (!Attachment.isSafeUrl(url) || !Uri.parse(url).host.contains('.')) return null;
    final a = Attachment(id: newId(), name: '', addedAt: DateTime.now(), url: url);
    return a.renamed(_title(title, a.host));
  }

  // ---------------------------------------------------------------- küçük resim

  static final Map<String, Future<File?>> _thumbs = {};
  static Future<Directory?>? _thumbDir;

  /// Listedeki küçük resim: fotoğrafın kendisi; videonun bir karesi ya da
  /// PDF'in ilk sayfası (bir kez üretilir, önbellekte durur). Üretilemezse null.
  static Future<File?> thumbnailOf(Attachment a) {
    final rel = a.file;
    if (rel == null) return Future.value();
    final file = AppPaths.imageFile(rel);
    if (file == null) return Future.value();
    if (a.kind == AttachmentKind.photo) return Future.value(file);
    final mime = a.mime ?? '';
    if (!mime.startsWith('video/') && mime != 'application/pdf') return Future.value();
    return _thumbs[rel] ??= _makeThumb(file, mime, rel);
  }

  static Future<File?> _makeThumb(File file, String mime, String rel) async {
    final dir = await (_thumbDir ??= _openThumbDir());
    if (dir == null) return null;
    final out = File(p.join(dir.path, '${p.basenameWithoutExtension(rel)}.jpg'));
    if (await out.exists()) return out;
    return await PlatformBridge.thumbnail(file.path, mime, out.path) ? out : null;
  }

  static Future<Directory?> _openThumbDir() async {
    try {
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'ek-onizleme'));
      await dir.create(recursive: true);
      return dir;
    } on Object {
      return null; // testlerde geçici klasör yok
    }
  }
}
