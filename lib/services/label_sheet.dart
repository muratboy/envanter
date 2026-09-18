import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Etiket boyu: A4 sayfaya kaç sütun, kaç satır.
enum LabelSize {
  small(4, 6),
  medium(3, 4),
  large(2, 3);

  const LabelSize(this.columns, this.rows);

  final int columns;
  final int rows;

  int get perPage => columns * rows;

  int pagesFor(int labels) => labels == 0 ? 0 : (labels + perPage - 1) ~/ perPage;
}

/// Sayfadaki tek etiket.
class LabelEntry {
  const LabelEntry({
    required this.payload,
    required this.title,
    required this.caption,
    required this.color,
  });

  /// QR'ın içeriği ([QrService.payloadFor]).
  final String payload;
  final String title;

  /// Başlığın altında küçük yazı: kaydın yeri.
  final String caption;

  /// Kart rengi (ARGB); etiketin üstünde ince bir şerit olur.
  final int color;
}

/// Yazdırılıp kesilecek A4 QR etiket sayfası. Kutulara yapıştırılır; okutunca
/// kayıt açılır. QR vektör çizilir (baskıda keskin kalır), etiketler arasına
/// kesik kesim çizgisi konur.
class LabelSheet {
  static const _ink = PdfColor.fromInt(0xFF22201C);
  static const _muted = PdfColor.fromInt(0xFF77716A);
  static const _cut = PdfColor.fromInt(0xFFC9C3B8);

  /// [display] başlık, [body] alt yazı yazı tipi. Türkçe harfler için
  /// uygulamanın kendi yazı tipleri verilmeli; verilmezse PDF'in yerleşik
  /// Helvetica'sı kullanılır (yalnızca testlerde).
  static Future<Uint8List> build(
    List<LabelEntry> entries, {
    required LabelSize size,
    pw.Font? display,
    pw.Font? body,
    String? title,
  }) async {
    final doc = pw.Document(title: title, creator: 'Envanter');
    const format = PdfPageFormat.a4;
    const margin = 8 * PdfPageFormat.mm;
    final cellWidth = (format.width - 2 * margin) / size.columns;
    final cellHeight = (format.height - 2 * margin) / size.rows;
    // Kare QR hücrenin daha dar kenarına göre; altında iki satır ad ve yer kalsın.
    final qr = [cellWidth * 0.62, cellHeight * 0.58].reduce((a, b) => a < b ? a : b);
    final (nameSize, captionSize) = switch (size) {
      LabelSize.small => (8.5, 6.0),
      LabelSize.medium => (11.0, 7.0),
      LabelSize.large => (15.0, 8.5),
    };

    for (var start = 0; start < entries.length; start += size.perPage) {
      final page = entries.skip(start).take(size.perPage).toList();
      doc.addPage(pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var r = 0; r * size.columns < page.length; r++)
              pw.Row(
                children: [
                  for (final e in page.skip(r * size.columns).take(size.columns))
                    _label(e,
                        width: cellWidth,
                        height: cellHeight,
                        qr: qr,
                        nameSize: nameSize,
                        captionSize: captionSize,
                        display: display,
                        body: body),
                ],
              ),
          ],
        ),
      ));
    }
    return doc.save();
  }

  static pw.Widget _label(
    LabelEntry e, {
    required double width,
    required double height,
    required double qr,
    required double nameSize,
    required double captionSize,
    pw.Font? display,
    pw.Font? body,
  }) {
    // Kart rengiyle ince şerit: kutudaki etiket destedeki kartla eşleşsin.
    final band = PdfColor.fromInt(e.color | 0xFF000000);
    return pw.Container(
      width: width,
      height: height,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _cut, width: 0.5, style: pw.BorderStyle.dashed),
      ),
      child: pw.Column(
        children: [
          pw.Container(height: 2.2 * PdfPageFormat.mm, color: band),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(4, 5, 4, 4),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
                    data: e.payload,
                    width: qr,
                    height: qr,
                    color: _ink,
                    drawText: false,
                  ),
                  pw.SizedBox(height: nameSize * 0.6),
                  pw.Text(
                    e.title,
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: display, fontSize: nameSize, color: _ink),
                  ),
                  if (e.caption.isNotEmpty) ...[
                    pw.SizedBox(height: 1.5),
                    pw.Text(
                      e.caption,
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: body, fontSize: captionSize, color: _muted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
