import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resimler diske goreli yolla kaydedilir; mutlak yol cihaz/kurulum
/// değişince gecersiz olabiliyor.
class AppPaths {
  /// Açık envanterin klasörü (fotoğrafları `images/` altında). Açılışta ve
  /// envanter değişince atanır; testler iki cihazı taklit ederken değiştirir.
  static late String docsDir;

  /// Klasör atandı mı (yalnızca mağazayı sınayan testlerde atanmaz).
  static bool isSet = false;

  /// Uygulamanın kök klasörü: envanterden bağımsız dosyalar (kişinin kendi
  /// fotoğrafı) burada. Atanmadıysa (testler) açık envanterin klasörü.
  static String? _root;
  static String get rootDir => _root ?? docsDir;

  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _root = dir.path;
    useDirectory(dir.path);
  }

  /// Belgeler klasörünü ayarlar ve resim klasörünün var olduğundan emin olur.
  static void useDirectory(String path) {
    docsDir = path;
    isSet = true;
    _resolved.clear();
    final images = Directory(p.join(docsDir, 'images'));
    if (!images.existsSync()) images.createSync(recursive: true);
    // Ekler (belge, video...) ayrı klasörde: fotoğraflarla karışmasın.
    final files = Directory(p.join(docsDir, 'files'));
    if (!files.existsSync()) files.createSync(recursive: true);
  }

  static String abs(String relative) => p.join(docsDir, relative);

  /// Kartlar kaydırma sirasinda her karede yeniden cizildigi için
  /// dosya varligi sorgusu önbellekleniyor.
  static final Map<String, File?> _resolved = {};

  static File? imageFile(String? relative) {
    if (relative == null || relative.isEmpty) return null;
    return _resolved.putIfAbsent(relative, () {
      final f = File(abs(relative));
      return f.existsSync() ? f : null;
    });
  }

  /// Kökteki (envanterden bağımsız) bir fotoğraf; ör. kişinin kendi fotoğrafı.
  static File? rootImageFile(String? relative) {
    if (relative == null || relative.isEmpty) return null;
    final f = File(p.join(rootDir, relative));
    return f.existsSync() ? f : null;
  }

  /// Dosya silindiginde ya da degistiginde önbelleği dusur.
  static void forget(String? relative) {
    if (relative != null) _resolved.remove(relative);
  }
}
