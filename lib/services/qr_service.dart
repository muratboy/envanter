import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/node.dart';

/// Okunan kod: uygulamanın kendi QR etiketi (kayıt kimliği) ya da bir ürünün
/// barkodu ([barcode]; o zaman [id] boştur, kayıt barkoda göre aranır).
class ScannedCode {
  const ScannedCode({required this.id, required this.isContainer}) : barcode = null;
  const ScannedCode.barcode(String this.barcode)
      : id = '',
        isContainer = false;

  final String id;
  final bool isContainer;
  final String? barcode;
}

class QrService {
  /// Karta ozel, ileride okutulabilecek adres. Ad sadece insan okusun diye.
  static String payloadFor(Node node) {
    final kind = node.isContainer ? 'container' : 'item';
    return 'envanter://$kind/${node.id}?n=${Uri.encodeComponent(node.trimmedName)}';
  }

  /// Okunan kodu çözer. Bu envantere ait değilse null döner.
  static ScannedCode? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'envanter') return null;
    final kind = uri.host;
    if (kind != 'container' && kind != 'item') return null;
    final id = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    if (id.isEmpty) return null;
    return ScannedCode(id: id, isContainer: kind == 'container');
  }

  /// [boundaryKey] ile isaretlenmis alani PNG'ye cevirip paylasir.
  static Future<void> shareBoundary(
    GlobalKey boundaryKey, {
    required String fileName,
    String? text,
  }) async {
    final bytes = await capture(boundaryKey);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$fileName.png'));
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')], text: text),
    );
  }

  static Future<Uint8List?> capture(GlobalKey boundaryKey) async {
    final object = boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    final image = await object.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  /// Dosya adinda kullanilamayacak karakterleri temizler.
  static String safeFileName(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[^\w\s-]'), '').trim().replaceAll(RegExp(r'\s+'), '_');
    return cleaned.isEmpty ? 'qr' : cleaned;
  }
}
