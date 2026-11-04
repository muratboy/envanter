import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/node.dart';
import '../services/image_service.dart';
import '../services/platform_bridge.dart';
import '../services/qr_service.dart';
import '../state/inventory_store.dart';
import '../core/theme.dart';

/// Önceki tarayıcı ekranı kapanırken kamerayı bırakması biraz sürüyor.
/// Yeni ekran onu beklemezse yerel taraf "kamera zaten çalışıyor" diyor ve
/// önizleme hiç açılmıyordu.
Future<void> _cameraReleased = Future<void>.value();

/// Kart QR'ını ya da ürün barkodunu okutma ekranı. Tanıdık bir kod görünce
/// kapanır ve çözülen kimliği (ya da barkodu) geri verir; tanımadığı QR
/// kodlarını sessizce yok sayar.
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, this.barcodeOnly = false, this.serialCount = false});

  /// Yalnızca ürün barkodu aranıyor (düzenleyicide eşyaya barkod kaydederken):
  /// QR kodları yok sayılır.
  final bool barcodeOnly;

  /// Seri sayım düğmesi (okunan her eşya bir artar): yalnızca genel tarayıcıda. Sayımın ve düzenleyicinin
  /// tarayıcısında da görünüyordu; sayımda okutulanları sayım listesine değil doğrudan kayıtlara yazıyordu.
  final bool serialCount;

  /// Ürün barkodu sayılan biçimler (zxing-cpp'nin adlarıyla). Sağlaması olanlar (EAN/UPC, Code 128) ve
  /// etiketlerde yaygın Code 39 (standart: genişletilmiş yorumu ve eczane türevleri okunmaz); sağlamasız
  /// ITF ve Codabar yanlış okunabildiği için yok.
  static const productFormats = ['EAN_13', 'EAN_8', 'UPC_A', 'UPC_E', 'CODE_128', 'CODE_39_STD'];

  /// Kartların QR etiketi: standart QR (Micro QR ve rMQR'a bakılmaz).
  static const qrFormat = 'QR_CODE_MODEL_2';

  @override
  State<ScanPage> createState() => _ScanPageState();
}

/// Kameranın açılamama nedeni: izin verilmediyse "yeniden dene" düğmesi yok (izin ayarlardan verilir).
enum _CameraProblem { permission, busy }

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  /// Kamera `camera` eklentisiyle açılır (seri eklemedeki gibi), kareleri yerel taraftaki zxing-cpp okur.
  /// Önceki tarayıcının ML Kit'i (mobile_scanner) kapalı kaynaktı: uygulama F-Droid'e giremiyordu, Google'a
  /// kullanım ölçümü de gönderiyordu. Başlatmayı kendimiz yönetiyoruz: kamera, önceki ekrandan ya da
  /// uygulama arka plandan dönerken hâlâ açık olabiliyor.
  CameraController? _camera;
  CameraLensDirection _lens = CameraLensDirection.back;
  _CameraProblem? _problem;
  bool _torch = false;

  /// Uygulama arka planda: o sırada açılışı biten kamera hemen bırakılır.
  bool _away = false;

  /// Kareyi dikleştiren açı (kameranın sensör yönü, telefon dikken); öteki yönleri okuyucu kendisi dener.
  int _rotation = 90;
  late final _formats = [if (!widget.barcodeOnly) ScanPage.qrFormat, ...ScanPage.productFormats];

  /// Bir kare okunurken gelenler atlanır: yerel taraf hep yeni kareyle uğraşsın, kuyruk birikmesin.
  bool _reading = false;
  final _seen = SeenCodes();

  bool _handled = false;
  bool _sawForeignCode = false;
  bool _starting = false;
  bool _serialMode = false;
  int _serialCount = 0;
  String? _lastScannedText;
  DateTime? _lastScannedAt;
  String? _serialStatusMessage;
  Timer? _statusTimer;

  /// Seri sayımın yazımları sırayla: art arda okunan iki eşya birbirinin adedini ezmesin.
  Future<void> _counting = Future.value();

  void _showStatus(String msg) {
    _statusTimer?.cancel();
    setState(() => _serialStatusMessage = msg);
    _statusTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _serialStatusMessage = null);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_start()));
  }

  /// Kamerayı açar. Önce önceki ekranın kamerayı bırakması beklenir; yine de
  /// tutulu kalmışsa birkaç kez yeniden denenir (kamera bırakılması
  /// yerel tarafta birkaç yüz milisaniye sürebiliyor).
  Future<void> _start({int attempt = 0}) async {
    if (_starting || !mounted || _handled || _camera != null) return;
    _starting = true;
    CameraController? camera;
    try {
      await _cameraReleased;
      if (!mounted) return;
      if (!await ImageService.ensureCamera()) {
        if (mounted) setState(() => _problem = _CameraProblem.permission);
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('none', 'no camera');
      final description = cameras.firstWhere((c) => c.lensDirection == _lens, orElse: () => cameras.first);
      // 720p: küçük barkod da okunur; her kare yerel tarafa gidip geldiği için daha büyüğü boşuna yük.
      camera = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await camera.initialize();
      if (!mounted || _handled || _away) {
        _release(camera);
        return;
      }
      _rotation = description.sensorOrientation;
      await camera.startImageStream(_onFrame);
      setState(() {
        _camera = camera;
        _problem = null;
        _torch = false;
      });
    } on Object catch (e) {
      if (camera != null) _release(camera);
      final denied = e is CameraException && e.code == 'CameraAccessDenied';
      if (denied || attempt >= 3 || !mounted) {
        if (mounted) setState(() => _problem = denied ? _CameraProblem.permission : _CameraProblem.busy);
        return;
      }
      _starting = false;
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      if (!mounted) return;
      await _start(attempt: attempt + 1);
    } finally {
      _starting = false;
    }
  }

  /// Kamerayı bırakır; sonraki tarayıcı ([_cameraReleased]) bitmesini bekler.
  void _release(CameraController camera) {
    _cameraReleased = () async {
      try {
        if (camera.value.isStreamingImages) await camera.stopImageStream();
      } on Object {
        // Akış zaten durmuş olabilir.
      }
      try {
        await camera.dispose();
      } on Object {
        // Zaten bırakılmış.
      }
    }();
  }

  /// Kamerayı kapatır (arka plana geçerken, kamera değişirken, çıkarken).
  void _stop() {
    final camera = _camera;
    if (camera == null) return;
    _camera = null;
    _torch = false;
    _release(camera);
    if (mounted) setState(() {});
  }

  /// Fener; ön kamerada ya da fenersiz telefonda hiçbir şey olmaz.
  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      await camera.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torch = !_torch);
    } on Object {
      // Fener yok.
    }
  }

  /// Ön ve arka kamera arasında geçer.
  Future<void> _switchCamera() async {
    _lens = _lens == CameraLensDirection.back ? CameraLensDirection.front : CameraLensDirection.back;
    _stop();
    await _start();
  }

  /// Kameranın karesi: yalnızca parlaklık düzlemi (Y) okunmaya gider, kod okumak için renk gerekmez.
  void _onFrame(CameraImage image) {
    if (_reading || _handled || image.planes.isEmpty) return;
    final plane = image.planes.first;
    _reading = true;
    unawaited(PlatformBridge.readBarcodes(
      bytes: plane.bytes,
      width: image.width,
      height: image.height,
      stride: plane.bytesPerRow,
      rotation: _rotation,
      formats: _formats,
    ).then((codes) {
      if (mounted && !_handled && codes.isNotEmpty) _onDetect(_seen.fresh(codes, DateTime.now()));
    }).whenComplete(() => _reading = false));
  }

  /// Ekrandan çıkmadan önce kamerayı bırak: bir sonraki tarayıcı beklemesin.
  Future<void> _close([ScannedCode? code]) async {
    final navigator = Navigator.of(context);
    _handled = true;
    _statusTimer?.cancel();
    _stop();
    await _cameraReleased;
    if (mounted) {
      if (_serialCount > 0) {
        final messenger = ScaffoldMessenger.of(context);
        final s = InventoryScope.read(context).strings;
        messenger.showSnackBar(SnackBar(content: Text('${s.scanBatchFinished} ($_serialCount)')));
      }
      navigator.pop(code);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted || _handled) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _away = false;
        unawaited(_start());
      case AppLifecycleState.inactive:
        // Arka planda kamera bırakılmaz; dönünce yeniden açılır.
        _away = true;
        _stop();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Sonraki tarayıcı, kamera gerçekten bırakılana kadar beklesin.
    final camera = _camera;
    _camera = null;
    if (camera != null) _release(camera);
    super.dispose();
  }

  void _onDetect(List<({String text, bool qr})> codes) {
    if (_handled) return;
    if (_serialMode) {
      final store = InventoryScope.read(context);
      final s = store.strings;
      for (final barcode in codes) {
        final raw = barcode.text;
        String? text;
        Node? matchNode;

        if (!barcode.qr) {
          text = Node.cleanBarcode(raw);
          if (text != null) {
            final matches = store.byBarcode(text);
            if (matches.isNotEmpty) matchNode = matches.first;
          }
        } else if (!widget.barcodeOnly) {
          final code = QrService.parse(raw);
          if (code != null) {
            text = code.id;
            matchNode = store.byId(code.id);
          }
        }

        if (text == null) continue;

        final now = DateTime.now();
        if (_lastScannedText == text &&
            _lastScannedAt != null &&
            now.difference(_lastScannedAt!) < const Duration(milliseconds: 1500)) {
          continue;
        }

        _lastScannedText = text;
        _lastScannedAt = now;

        HapticFeedback.mediumImpact();

        if (matchNode != null && matchNode.isContainer) {
          _showStatus(s.serialFolderSkipped(store.nameOf(matchNode)));
        } else if (matchNode != null && store.isLive(matchNode)) {
          final node = matchNode;
          _serialCount++;
          // Mağazanın sayma yolu (paket kuralı): doğrudan `copyWith(quantity: …)` yazılıyordu, paketler toplamı
          // tutmuyor, klasöre ve çöpteki kayda da adet konuyordu.
          _counting = _counting.then((_) async {
            final quantity = await store.countOne(node.id);
            if (mounted && quantity != null) _showStatus(s.stockCounted(store.nameOf(node), quantity));
          });
        } else {
          _showStatus(s.unknownBarcodeScan);
        }
        return;
      }
      return;
    }

    for (final barcode in codes) {
      final raw = barcode.text;
      if (!barcode.qr) {
        final text = Node.cleanBarcode(raw);
        if (text == null) continue;
        unawaited(_close(ScannedCode.barcode(text)));
        return;
      }
      if (widget.barcodeOnly) continue;
      final code = QrService.parse(raw);
      if (code == null) {
        if (!_sawForeignCode && mounted) setState(() => _sawForeignCode = true);
        continue;
      }
      unawaited(_close(code));
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = InventoryScope.of(context).strings;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(
          widget.barcodeOnly ? s.scanBarcode : s.scanQr,
          style: const TextStyle(color: Colors.white, fontFamily: kDisplayFont, fontSize: 23, fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => unawaited(_close()),
        ),
        actions: [
          if (widget.serialCount && !widget.barcodeOnly)
            IconButton(
              icon: Icon(_serialMode ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded),
              color: _serialMode ? Colors.amber : Colors.white,
              tooltip: s.serialScanMode,
              onPressed: () => setState(() => _serialMode = !_serialMode),
            ),
          IconButton(
            icon: const Icon(Icons.flashlight_on_rounded),
            tooltip: 'Flash',
            onPressed: () => unawaited(_toggleTorch()),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => unawaited(_switchCamera()),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _preview(context),
          const _ScanFrame(),
          if (_serialMode)
            Positioned(
              top: kToolbarHeight + MediaQuery.paddingOf(context).top + 16,
              left: 24,
              right: 24,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _serialStatusMessage != null ? Colors.amber.shade800 : Colors.black87,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _serialStatusMessage != null ? Icons.check_circle_rounded : Icons.barcode_reader,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _serialStatusMessage ?? '${s.serialScanMode}: $_serialCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _serialMode
                      ? s.serialScanHint
                      : (widget.barcodeOnly ? s.scanBarcodeHint : s.scanQrHint),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                if (_sawForeignCode) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      s.qrNotRecognized,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Önizleme ekranı doldurur (kadraj ortada); kamera açılamadıysa nedeni ve "yeniden dene".
  Widget _preview(BuildContext context) {
    final camera = _camera;
    if (camera != null && camera.value.isInitialized) {
      return ValueListenableBuilder<CameraValue>(
        valueListenable: camera,
        builder: (context, value, child) {
          final size = value.previewSize;
          if (size == null) return Center(child: child);
          // Önizlemenin boyutu kameranın yatay yönünde. Hangi yönde çizileceğine CameraPreview'un
          // kendisi gibi karar verilir; yoksa kutu önizlemeye uymaz, ekran dolmaz.
          final turned = value.previewPauseOrientation ?? value.lockedCaptureOrientation ?? value.deviceOrientation;
          final landscape =
              turned == DeviceOrientation.landscapeLeft || turned == DeviceOrientation.landscapeRight;
          return ClipRect(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: landscape ? size.width : size.height,
                height: landscape ? size.height : size.width,
                child: child,
              ),
            ),
          );
        },
        child: CameraPreview(camera),
      );
    }
    final problem = _problem;
    if (problem == null) return const SizedBox.shrink();
    final s = InventoryScope.of(context).strings;
    // Ham hata metni kullanıcıya bir şey anlatmıyor; nedenine göre
    // kendi cümlemizi ve bir "yeniden dene" düğmesini gösteriyoruz.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              problem == _CameraProblem.permission ? s.cameraPermissionNeeded : s.cameraBusy,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            if (problem != _CameraProblem.permission) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () {
                  setState(() => _problem = null);
                  unawaited(_start());
                },
                child: Text(s.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kameranın gördüğü kodlar. Görüş alanında duran kod her karede yeniden okunur; yalnızca bir süre
/// ([gone]) okunmadıktan sonra yeniden görününce yeni sayılır. Önceki tarayıcının "aynısını bir daha
/// bildirme" kuralı son okunanı kod gözden çıkınca da unutmuyordu: seri sayımda aynı üründen ikinci tane,
/// arada başka bir kod okutulmadan hiç sayılmıyordu.
@visibleForTesting
class SeenCodes {
  static const gone = Duration(seconds: 1);

  final _at = <String, DateTime>{};

  /// [codes]'dan yeni görünenler; hepsinin son görülme anı [now] olur.
  List<({String text, bool qr})> fresh(List<({String text, bool qr})> codes, DateTime now) {
    final fresh = [
      for (final code in codes)
        if (!_recent(code.text, now)) code,
    ];
    for (final code in codes) {
      _at[code.text] = now;
    }
    _at.removeWhere((_, at) => now.difference(at) >= gone * 10);
    return fresh;
  }

  bool _recent(String text, DateTime now) {
    final at = _at[text];
    return at != null && now.difference(at) < gone;
  }
}

/// Kadrajı belli eden köşe çizgileri.
class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 250,
        height: 250,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2.5),
          borderRadius: BorderRadius.circular(28),
        ),
      ),
    );
  }
}
