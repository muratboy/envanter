import 'package:flutter/services.dart';

/// MainActivity'deki küçük yerel işler.
class PlatformBridge {
  static const _channel = MethodChannel('envanter/platform');

  /// Kamera izni (image_picker'ın kamera akışından önce).
  static Future<bool> ensureCamera() async {
    try {
      return await _channel.invokeMethod<bool>('ensureCamera') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return true; // yerel taraf yoksa (ör. testler) akışı engelleme
    }
  }

  /// Kullanıcıya dosya seçtirir (yedekten geri yükleme). Seçilen dosya
  /// önbelleğe kopyalanır; yolu döner, vazgeçilirse null.
  ///
  /// [onCopying]: dosya seçildi, kopyalama başladı (büyük bir yedekte saniyeler
  /// sürer; arayüz o an "içe aktarılıyor" diyebilsin).
  static Future<String?> pickFile({void Function()? onCopying}) async {
    _onCopying = onCopying;
    if (onCopying != null) _listen();
    try {
      return await _channel.invokeMethod<String>('pickFile');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } finally {
      _onCopying = null;
    }
  }

  static void Function()? _onCopying;

  /// Ana ekran kısayolu (uygulama simgesine uzun basınca) ya da widget'a
  /// dokunma: hangisi ("scan", "search", "new_item", "shopping"). Bir kez döner;
  /// alınınca silinir.
  static Future<String?> takeShortcut() async {
    try {
      return await _channel.invokeMethod<String>('takeShortcut');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Uygulama açıkken bir kısayola basıldı; [onReady] kısayolu
  /// [takeShortcut] ile alır.
  static void listenShortcuts(void Function() onReady) {
    _onShortcut = onReady;
    _listen();
  }

  static void Function()? _onShortcut;

  /// Arka plan işi (`BackgroundJob.kt`) uygulama yaşarken bu motora devredildi.
  static Future<void> Function(String task)? onBackgroundTask;

  /// Arka planda açılan motordan iş bitmeden çıkılması istendi (uygulama açılıyor).
  static void Function()? onStop;

  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'shortcut':
          _onShortcut?.call();
        case 'backgroundTask':
          await onBackgroundTask?.call(call.arguments as String? ?? 'sync');
        case 'stop':
          onStop?.call();
        case 'copying':
          _onCopying?.call();
      }
      return null;
    });
  }

  /// Arka plan motorunda: "backgroundTask"/"stop" haberleri dinlensin.
  static void listen() => _listen();

  /// Açılışta: arka planda açılmış bir motor veritabanını bıraksın. Yerel taraf
  /// yoksa ya da yanıt gelmezse beklemeden geçilir.
  static Future<void> waitBackgroundIdle() async {
    try {
      await _channel.invokeMethod<void>('waitBackgroundIdle').timeout(const Duration(seconds: 12));
    } on Object {
      // Beklenecek bir şey yok.
    }
  }

  /// Arka plan motoru işini bitirdi; yerel taraf motoru kapatır.
  static Future<void> backgroundDone() async {
    try {
      await _channel.invokeMethod<void>('backgroundDone');
    } on Object {
      // Motor zaten kapanıyor.
    }
  }

  /// Sağ kenardaki kulpların dikeydeki yeri (mantıksal piksel): Android'in
  /// "geri" hareketi o şeritte devre dışı kalsın. Ekran dönünce yeri değişir.
  static Future<void> setEdgeExclusion(double top, double bottom) async {
    try {
      await _channel.invokeMethod<void>('setEdgeExclusion', {'top': top, 'bottom': bottom});
    } on Object {
      // Yerel taraf yok (testler) ya da eski Android: şerit yok.
    }
  }

  /// Telefonun saati otomatik mi (ağdan). Bilinemezse (testler) otomatik sayılır.
  static Future<bool> autoTime() async {
    try {
      return await _channel.invokeMethod<bool>('autoTime') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// Ana ekrandaki alışveriş listesi widget'ının verisini yazar (JSON; bkz.
  /// `shopping_widget.dart`). Yazıldıysa true; yerel taraf yoksa (testler) null.
  static Future<bool?> updateShoppingWidget(String payload) async {
    try {
      return await _channel.invokeMethod<bool>('updateShoppingWidget', payload);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return null;
    }
  }

  /// Otomatik yedek için klasör seçtirir; izin kalıcı alınır. Klasörün adresi
  /// ve görünen adı döner, vazgeçilirse null.
  static Future<({String uri, String name})?> pickFolder() async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('pickFolder');
      final uri = r?['uri'];
      if (uri is! String) return null;
      return (uri: uri, name: r?['name'] is String ? r!['name'] as String : uri);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> releaseFolder(String uri) async {
    try {
      await _channel.invokeMethod<void>('releaseFolder', {'uri': uri});
    } on PlatformException {
      // Zaten bırakılmış.
    } on MissingPluginException {
      // Testler.
    }
  }

  /// [path]'teki dosyayı klasöre [name] adıyla yazar; klasörde en yeni [keep]
  /// yedek kalır. İzin geri alındıysa ya da yazılamadıysa false.
  static Future<bool> writeBackup(String uri, String path, String name, int keep) async {
    try {
      return await _channel.invokeMethod<bool>('writeBackup', {'uri': uri, 'path': path, 'name': name, 'keep': keep}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Ek için dosya seçtirir (birden çok olabilir); seçilenler [dir]'e
  /// kopyalanır. Her biri için ad ve — kopyalandıysa — klasördeki dosya adı,
  /// türü, boyutu döner; [max] bayttan büyük olan kopyalanmaz (`tooLarge`).
  /// Vazgeçilirse ya da yerel taraf yoksa boş liste.
  static Future<List<PickedDocument>> pickDocuments(String dir, {required int max}) async {
    try {
      final list = await _channel.invokeListMethod<Object?>('pickDocuments', {'dir': dir, 'max': max});
      return [
        for (final e in list ?? const [])
          if (e is Map)
            PickedDocument(
              name: e['name'] is String ? e['name'] as String : '',
              file: e['file'] is String ? e['file'] as String : null,
              mime: e['mime'] is String ? e['mime'] as String : null,
              size: e['size'] is int ? e['size'] as int : 0,
              tooLarge: e['tooLarge'] == true,
            ),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Seri ekleme: galeriden birden çok fotoğraf seçtirir. Fotoğrafların kendisi değil, adresleri ve
  /// adları döner (hemen; 200 fotoğrafta da); her biri sonra [importImage] ile alınır. Vazgeçilirse ya da
  /// yerel taraf yoksa boş liste; galeri uygulaması yoksa [PlatformException].
  static Future<List<({String uri, String name})>> pickImages() async {
    try {
      final list = await _channel.invokeListMethod<Object?>('pickImages');
      return [
        for (final e in list ?? const [])
          if (e is Map && e['uri'] is String)
            (uri: e['uri'] as String, name: e['name'] is String ? e['name'] as String : ''),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Galeriden seçilen fotoğrafı küçültüp (en uzun kenar [max]) [out]'a JPEG yazar; yerelde birkaç tanesi
  /// birden işlenir. Alınamadıysa false.
  static Future<bool> importImage(String uri, String out, {int max = 1800, int quality = 88}) async {
    try {
      final args = {'uri': uri, 'out': out, 'max': max, 'quality': quality};
      return await _channel.invokeMethod<bool>('importImage', args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Dosyayı o türü açan uygulamada açar; [name] orada görünen addır. Açan
  /// uygulama yoksa false.
  static Future<bool> openFile(String path, String? mime, {String? name}) async {
    try {
      return await _channel.invokeMethod<bool>('openFile', {'path': path, 'mime': mime, 'name': name}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Bağlantıyı tarayıcıda (ya da o siteyi açan uygulamada) açar.
  static Future<bool> openUrl(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Videonun bir karesini ya da PDF'in ilk sayfasını [out]'a küçük resim
  /// olarak yazar. Yazılamadıysa (tür desteklenmiyor, testler) false.
  static Future<bool> thumbnail(String path, String mime, String out, {int size = 320}) async {
    try {
      return await _channel.invokeMethod<bool>('thumbnail', {'path': path, 'mime': mime, 'out': out, 'size': size}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Ortak kullanım açıkken Wi-Fi yayın kilidi.
  static Future<void> setMulticastLock(bool held) async {
    try {
      await _channel.invokeMethod<void>('setMulticastLock', held);
    } on PlatformException {
      // Kilit alınamazsa bulma yine denenir; bazı cihazlarda gerekmiyor.
    } on MissingPluginException {
      // Testler.
    }
  }
}

/// Kullanıcının ek olarak seçtiği bir dosya (bkz. [PlatformBridge.pickDocuments]).
class PickedDocument {
  const PickedDocument({required this.name, this.file, this.mime, this.size = 0, this.tooLarge = false});

  /// Dosyanın kullanıcıya görünen adı ("Matkap kılavuzu.pdf").
  final String name;

  /// Kopyalandığı klasördeki adı; kopyalanamadıysa null.
  final String? file;
  final String? mime;
  final int size;
  final bool tooLarge;
}
