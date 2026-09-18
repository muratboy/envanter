import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/app_paths.dart';
import 'platform_bridge.dart';

class ImageService {
  static final _picker = ImagePicker();
  static const _uuid = Uuid();

  /// Kamerayı kullanmadan önce izin. QR okuyucu için CAMERA iznini
  /// tanımladığımızdan, image_picker'ın kamera akışı da artık izin
  /// verilmiş olmasını bekliyor.
  static Future<bool> ensureCamera() => PlatformBridge.ensureCamera();

  /// Kamera ya da galeriden seçip uygulama klasörüne kopyalar.
  /// Geriye belgeler klasörüne göre göreli yol döner. [personal]: envanterden
  /// bağımsız fotoğraf (kişinin kendisi); açık envanterin değil kökün klasörüne.
  static Future<String?> pick(ImageSource source, {bool personal = false}) async {
    if (source == ImageSource.camera && !await ensureCamera()) return null;
    final shot = await _picker.pickImage(
      source: source,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 88,
    );
    if (shot == null) return null;
    final ext = p.extension(shot.path).isEmpty ? '.jpg' : p.extension(shot.path);
    final relative = p.join('images', '${_uuid.v4()}$ext');
    final base = personal ? AppPaths.rootDir : AppPaths.docsDir;
    Directory(p.join(base, 'images')).createSync(recursive: true);
    await File(shot.path).copy(p.join(base, relative));
    AppPaths.forget(relative);
    return relative;
  }

  /// Seri ekleme: galeriden birden çok fotoğraf seçtirir; seçim sırasıyla (adres, fotoğrafın adı)
  /// çiftleri. Fotoğraflar henüz alınmadı, her biri [importPicked] ile alınır: 200 fotoğrafta da seçim hemen
  /// döner, alma sürerken ilerleme gösterilir (image_picker hepsini bitirene dek hiçbir şey döndürmüyordu).
  static Future<List<(String, String)>> pickGallery() => pickGalleryImages();

  /// Sistemin galeri seçicisi; testlerde yok, yerine sahte (adres, ad) çiftleri veren bir işlev konur.
  @visibleForTesting
  static Future<List<(String, String)>> Function() pickGalleryImages = _pickGalleryImages;

  static Future<List<(String, String)>> _pickGalleryImages() async =>
      [for (final picked in await PlatformBridge.pickImages()) (picked.uri, picked.name)];

  /// Seçilen fotoğrafı envanterin `images/` klasörüne alır (en uzun kenarı 1800 px, JPEG). Göreli yol;
  /// alınamadıysa null.
  static Future<String?> importPicked(String uri) async {
    final relative = p.join('images', '${_uuid.v4()}.jpg');
    Directory(p.join(AppPaths.docsDir, 'images')).createSync(recursive: true);
    if (!await importImage(uri, p.join(AppPaths.docsDir, relative))) return null;
    AppPaths.forget(relative);
    return relative;
  }

  /// Fotoğrafı yerelde küçültüp yazan işlev; testlerde dosya kopyalayan bir işlev konur.
  @visibleForTesting
  static Future<bool> Function(String uri, String out) importImage = PlatformBridge.importImage;

  /// Seçilen fotoğrafın adından (galerideki dosya adı) eşya adı: uzantısız.
  static String nameOfImage(String fileName) => p.basenameWithoutExtension(fileName.trim()).trim();

  /// Kişinin eski fotoğrafını siler ([pick] `personal` ile kaydedilen).
  static void discardPersonal(String? relative) {
    try {
      AppPaths.rootImageFile(relative)?.deleteSync();
    } on FileSystemException {
      // Zaten yoksa sorun değil.
    }
  }

  /// Karttan kaldırılan resmi diskten de siler.
  static void discard(String? relative) {
    final f = AppPaths.imageFile(relative);
    AppPaths.forget(relative);
    if (f == null) return;
    try {
      f.deleteSync();
    } on FileSystemException {
      // Dosya zaten yoksa sorun değil.
    }
  }
}
