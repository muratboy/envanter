import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/node.dart';
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

  /// Ürün barkodu sayılan biçimler. Sağlaması olanlar (EAN/UPC, Code 128) ve
  /// etiketlerde yaygın Code 39; sağlamasız ITF ve Codabar yanlış okunabildiği
  /// için yok.
  static const productFormats = [
    BarcodeFormat.ean13,
    BarcodeFormat.ean8,
    BarcodeFormat.upcA,
    BarcodeFormat.upcE,
    BarcodeFormat.code128,
    BarcodeFormat.code39,
  ];

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  /// Başlatmayı kendimiz yönetiyoruz: kamera, önceki ekrandan ya da uygulama
  /// arka plandan dönerken hâlâ açık olabiliyor ve üst üste gelen start()
  /// çağrıları "zaten çalışıyor" hatası veriyordu.
  late final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: [if (!widget.barcodeOnly) BarcodeFormat.qrCode, ...ScanPage.productFormats],
    autoStart: false,
  );

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
  /// tutulu kalmışsa durdurup birkaç kez yeniden denenir (kamera bırakılması
  /// yerel tarafta birkaç yüz milisaniye sürebiliyor).
  Future<void> _start({int attempt = 0}) async {
    if (_starting || !mounted) return;
    _starting = true;
    try {
      await _cameraReleased;
      if (!mounted) return;
      await _controller.start();
    } on MobileScannerException catch (e) {
      final hopeless = e.errorCode == MobileScannerErrorCode.permissionDenied ||
          e.errorCode == MobileScannerErrorCode.unsupported;
      if (hopeless || attempt >= 3 || !mounted) return;
      _starting = false;
      await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      if (!mounted) return;
      try {
        await _controller.stop();
      } on MobileScannerException {
        // Zaten durmuş olabilir.
      }
      return _start(attempt: attempt + 1);
    } finally {
      _starting = false;
    }
  }

  /// Ekrandan çıkmadan önce kamerayı bırak: bir sonraki tarayıcı beklemesin.
  Future<void> _close([ScannedCode? code]) async {
    final navigator = Navigator.of(context);
    _handled = true;
    _statusTimer?.cancel();
    await _controller.stop();
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
        unawaited(_start());
      case AppLifecycleState.inactive:
        // Arka planda kamera bırakılmaz; dönünce yeniden açılır.
        unawaited(_controller.stop());
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
    _cameraReleased = _controller.dispose().catchError((Object _) {});
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (_serialMode) {
      final store = InventoryScope.read(context);
      final s = store.strings;
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue;
        if (raw == null) continue;
        String? text;
        Node? matchNode;

        if (ScanPage.productFormats.contains(barcode.format)) {
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

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      if (ScanPage.productFormats.contains(barcode.format)) {
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
            onPressed: _controller.toggleTorch,
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: _controller.switchCamera,
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // Ham hata metni kullanıcıya bir şey anlatmıyor; nedenine göre
            // kendi cümlemizi ve bir "yeniden dene" düğmesini gösteriyoruz.
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      switch (error.errorCode) {
                        MobileScannerErrorCode.permissionDenied => s.cameraPermissionNeeded,
                        MobileScannerErrorCode.unsupported => s.cameraBusy,
                        _ => s.cameraBusy,
                      },
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    if (error.errorCode != MobileScannerErrorCode.permissionDenied) ...[
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () => unawaited(_start()),
                        child: Text(s.retry),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
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
