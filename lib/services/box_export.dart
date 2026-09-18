import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/money.dart';
import '../core/transitions.dart';
import '../data/library.dart';
import '../data/node.dart';
import '../services/qr_service.dart';
import '../state/inventory_store.dart';

/// Koli ve klasör içerik dökümü: PDF (yazdırılabilir QR başlıklı tablo) ve
/// CSV (Excel uyumlu UTF-8 BOM'lu liste) olarak dışa aktarma.
class BoxExportService {
  /// Klasörün içindeki tüm eşyaları ve alt klasörleri derinlik-öncelikli sırayla toplar.
  static List<Node> collectItems(InventoryStore store, Node container) {
    final list = <Node>[];
    void walk(String parentId) {
      for (final child in store.childrenOf(parentId)) {
        list.add(child);
        if (child.isContainer) {
          walk(child.id);
        }
      }
    }

    walk(container.id);
    return list;
  }

  /// PDF için yazı tiplerini yükler (Türkçe karakter desteği için).
  static Future<(pw.Font, pw.Font)> _fonts() async => (
        pw.Font.ttf(await rootBundle.load('assets/fonts/Fraunces-SemiBold.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-SemiBold.ttf')),
      );

  /// Koli ve içerik dökümünü A4 PDF olarak üretir.
  static Future<File> buildPdf(InventoryStore store, Node container) async {
    final s = store.strings;
    final (display, body) = await _fonts();
    final items = collectItems(store, container);
    final doc = pw.Document(title: '${store.nameOf(container)} - ${s.boxContentList}', creator: 'Envanter');

    const ink = PdfColor.fromInt(0xFF22201C);
    const muted = PdfColor.fromInt(0xFF77716A);
    const line = PdfColor.fromInt(0xFFE2DDD5);
    const headerBg = PdfColor.fromInt(0xFFF5F1E9);

    final containerName = store.nameOf(container);
    final path = store.pathLabel(container.id);
    final dateStr = s.formatDate(DateTime.now());
    final payload = QrService.payloadFor(container);

    final tableData = <List<String>>[
      [
        s.itemIndexCol,
        s.itemNameCol,
        s.itemQuantityCol,
        s.itemLocationCol,
        s.itemNoteCol,
        s.itemBarcodeCol,
      ],
      for (var i = 0; i < items.length; i++)
        () {
          final item = items[i];
          final name = store.nameOf(item);
          final qty = item.tracksQuantity
              ? '${item.quantity ?? 1}${item.unit != null ? " ${item.unit}" : ""}'
              : (item.isContainer ? '[${s.container}]' : '-');
          final relPath = store.pathLabelForParent(item.parentId, inDrawer: item.inDrawer);
          final note = item.quantity == 0 && !item.isContainer ? s.outOfStock : (item.note?.trim() ?? '');
          final barcode = item.barcode ?? '-';
          return [
            '${i + 1}',
            name,
            qty,
            relPath,
            note,
            barcode,
          ];
        }(),
    ];

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context ctx) {
          if (ctx.pageNumber > 1) {
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('$containerName · ${s.boxContentList}', style: pw.TextStyle(font: body, fontSize: 9, color: muted)),
                  pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: pw.TextStyle(font: body, fontSize: 9, color: muted)),
                ],
              ),
            );
          }
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 16),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        containerName,
                        style: pw.TextStyle(font: display, fontSize: 18, color: ink, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        '${s.boxContentList} · $dateStr · ${s.recordCount(items.length)}',
                        style: pw.TextStyle(font: body, fontSize: 10, color: muted),
                      ),
                      if (container.barcode != null) ...[
                        pw.SizedBox(height: 2),
                        pw.Text('${s.barcode}: ${container.barcode}', style: pw.TextStyle(font: body, fontSize: 9, color: muted)),
                      ],
                      if (path.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(path, style: pw.TextStyle(font: body, fontSize: 9, color: muted)),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium),
                  data: payload,
                  width: 58,
                  height: 58,
                  color: ink,
                  drawText: false,
                ),
              ],
            ),
          );
        },
        footer: (pw.Context ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Envanter', style: pw.TextStyle(font: body, fontSize: 8.5, color: muted)),
              pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: pw.TextStyle(font: body, fontSize: 8.5, color: muted)),
            ],
          ),
        ),
        build: (pw.Context ctx) => [
          pw.TableHelper.fromTextArray(
            context: ctx,
            data: tableData,
            border: pw.TableBorder.all(color: line, width: 0.5),
            headerStyle: pw.TextStyle(font: body, fontSize: 9, fontWeight: pw.FontWeight.bold, color: ink),
            cellStyle: pw.TextStyle(font: body, fontSize: 8.5, color: ink),
            headerDecoration: const pw.BoxDecoration(color: headerBg),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            columnWidths: const {
              0: pw.FixedColumnWidth(24),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(1.2),
              3: pw.FlexColumnWidth(2),
              4: pw.FlexColumnWidth(2),
              5: pw.FlexColumnWidth(1.5),
            },
            cellAlignments: const {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerLeft,
              4: pw.Alignment.centerLeft,
              5: pw.Alignment.centerLeft,
            },
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final safeName = containerName.replaceAll(RegExp(r'[^\w\s\.-]'), '_').trim();
    final file = File(p.join(dir.path, '${safeName}_icerik_dokumu.pdf'));
    await file.writeAsBytes(await doc.save(), flush: true);
    return file;
  }

  /// Değer dökümü (sigorta, taşınma): fiyatı olan her eşya yeri, adedi, birim fiyatı, tutarı,
  /// seri numarası ve alış tarihiyle; yerlere göre ara toplamlar, genel toplam ve fiyatı
  /// olmayanlar ayrı bir listede (döküm eksik görünmesin; sayıları başta yazar). [container]
  /// verilmezse bütün envanter (ana ekran, çekmece, kayıplar). Birimler ayrı toplanır (kur
  /// çevrimi yok). Manrope'ta olmayan para simgeleri (₼) Fraunces'tan çizilir.
  static Future<File> buildValuePdf(InventoryStore store, {Node? container}) async {
    final (title, bytes) = await valuePdf(store, container: container);
    final dir = await getTemporaryDirectory();
    final safeName = title.replaceAll(RegExp(r'[^\w\s\.-]'), '_').trim();
    final file = File(p.join(dir.path, '${safeName}_deger_dokumu.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// [buildValuePdf]'in kendisi: başlık ve PDF baytları (dosya yazmadan; testler de kullanır).
  static Future<(String, Uint8List)> valuePdf(InventoryStore store, {Node? container}) async {
    final s = store.strings;
    final (display, body) = await _fonts();
    final items = <Node>[];
    if (container != null) {
      items.addAll(collectItems(store, container).where((n) => !n.isContainer));
    } else {
      void walk(String id) {
        for (final c in store.childrenOf(id)) {
          c.isContainer ? walk(c.id) : items.add(c);
        }
      }

      for (final root in const [Roots.home, Roots.drawer, Roots.lost]) {
        walk(root);
      }
    }
    final priced = [for (final n in items) if (n.value != null) n];
    final unpriced = [for (final n in items) if (n.value == null) n];

    // Yer: bütün envanterde en üstteki klasör (ya da ana ekran / çekmece / kayıplar); klasör
    // dökümünde onun doğrudan alt klasörü (klasörün kendi içindekiler klasörün adıyla).
    String placeOf(Node n) {
      final chain = store.ancestorsOf(n.id);
      if (container != null) {
        final at = chain.indexWhere((a) => a.id == container.id);
        return at >= 0 && at + 1 < chain.length ? store.nameOf(chain[at + 1]) : store.nameOf(container);
      }
      if (chain.isEmpty) return n.isLost ? s.lostItems : (n.inDrawer ? s.drawer : s.home);
      final top = chain.first;
      if (top.isLost) return '${s.lostItems} / ${store.nameOf(top)}';
      return top.inDrawer ? '${s.drawer} / ${store.nameOf(top)}' : store.nameOf(top);
    }

    final grand = MoneyTotals();
    final groups = <String, List<Node>>{};
    final groupTotals = <String, MoneyTotals>{};
    for (final n in priced) {
      final place = placeOf(n);
      (groups[place] ??= []).add(n);
      (groupTotals[place] ??= MoneyTotals()).add(n.value!);
      grand.add(n.value!);
    }
    final main = grand.mainCurrency;
    int byValue(Node a, Node b) {
      final va = a.value!, vb = b.value!;
      if ((va.currency == main) != (vb.currency == main)) return va.currency == main ? -1 : 1;
      return vb.cents.compareTo(va.cents);
    }

    final places = groups.keys.toList()
      ..sort((a, b) {
        final c = groupTotals[b]!.centsIn(main ?? '').compareTo(groupTotals[a]!.centsIn(main ?? ''));
        return c != 0 ? c : a.compareTo(b);
      });
    for (final list in groups.values) {
      list.sort(byValue);
    }

    const ink = PdfColor.fromInt(0xFF22201C);
    const muted = PdfColor.fromInt(0xFF77716A);
    const line = PdfColor.fromInt(0xFFE2DDD5);
    const headerBg = PdfColor.fromInt(0xFFF5F1E9);
    final text = pw.TextStyle(font: body, fontFallback: [display], fontSize: 8.5, color: ink);
    final small = text.copyWith(fontSize: 9, color: muted);
    final bold = text.copyWith(fontWeight: pw.FontWeight.bold, fontSize: 9);

    final title = container != null
        ? store.nameOf(container)
        : (InventoryLibrary.current?.active.name.trim().isNotEmpty ?? false)
            ? InventoryLibrary.current!.active.name.trim()
            : s.appTitle;
    final date = s.formatDate(DateTime.now());
    final doc = pw.Document(title: '$title - ${s.valueReportTitle}', creator: 'Envanter');

    String qty(Node n) => n.quantity == null ? '1' : '${n.quantity}${n.unit != null ? ' ${n.unit}' : ''}';

    // [headers] satır başlıktır ve tablo sayfaya sığmayınca her sayfada tekrarlanır: yer adı ve ara
    // toplam tablonun kendi başlığında, sayfa sonunda tek başına kalmaz.
    pw.Widget table(List<List<String>> rows, Map<int, pw.TableColumnWidth> widths, Set<int> right, {int headers = 1}) =>
        pw.TableHelper.fromTextArray(
          data: rows,
          headerCount: headers,
          border: pw.TableBorder.all(color: line, width: 0.5),
          headerStyle: bold,
          cellStyle: text,
          headerDecoration: const pw.BoxDecoration(color: headerBg),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          columnWidths: widths,
          cellAlignments: {
            for (var i = 0; i < rows.first.length; i++)
              i: right.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
          },
        );

    var index = 0;
    final content = <pw.Widget>[];
    for (final place in places) {
      if (content.isNotEmpty) content.add(pw.SizedBox(height: 10));
      content.add(table(
        headers: 2,
        [
          ['', place, '${s.subtotal}: ${s.moneyTotals(groupTotals[place]!)}', '', '', '', '', ''],
          ['#', s.itemNameCol, s.itemLocationCol, s.itemQuantityCol, s.colUnitPrice, s.colAmount, s.colSerial, s.colPurchased],
          for (final n in groups[place]!)
            [
              '${++index}',
              store.nameOf(n),
              store.pathLabelForParent(n.parentId, inDrawer: n.inDrawer),
              qty(n),
              s.money(n.priceMoney!),
              s.money(n.value!),
              n.serial ?? '',
              n.purchasedAt == null ? '' : s.formatDate(n.purchasedAt!),
            ],
        ],
        const {
          0: pw.FixedColumnWidth(22),
          1: pw.FlexColumnWidth(2.6),
          2: pw.FlexColumnWidth(2.4),
          3: pw.FlexColumnWidth(0.9),
          4: pw.FlexColumnWidth(1.3),
          5: pw.FlexColumnWidth(1.3),
          6: pw.FlexColumnWidth(1.6),
          7: pw.FlexColumnWidth(1.1),
        },
        {0, 3, 4, 5},
      ));
    }
    if (places.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(table(
        [
          [s.valueByPlace, s.itemQuantityCol, s.colAmount],
          for (final place in places) [place, '${groups[place]!.length}', s.moneyTotals(groupTotals[place]!)],
          [s.grandTotal, '${priced.length}', s.moneyTotals(grand)],
        ],
        const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(0.8), 2: pw.FlexColumnWidth(2)},
        {1, 2},
      ));
    }
    if (unpriced.isNotEmpty) {
      content.add(pw.SizedBox(height: 14));
      content.add(table(
        headers: 2,
        [
          ['', '${s.unpricedSection} (${unpriced.length})', '', '', ''],
          ['#', s.itemNameCol, s.itemLocationCol, s.itemQuantityCol, s.colSerial],
          for (final (i, n) in unpriced.indexed)
            [
              '${i + 1}',
              store.nameOf(n),
              store.pathLabelForParent(n.parentId, inDrawer: n.inDrawer),
              qty(n),
              n.serial ?? '',
            ],
        ],
        const {
          0: pw.FixedColumnWidth(22),
          1: pw.FlexColumnWidth(3),
          2: pw.FlexColumnWidth(3),
          3: pw.FlexColumnWidth(0.9),
          4: pw.FlexColumnWidth(1.6),
        },
        {0, 3},
      ));
    }
    if (content.isEmpty) content.add(pw.Text(s.noValueYet, style: small));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => ctx.pageNumber > 1
            ? pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text('$title · ${s.valueReportTitle} · $date', style: small),
              )
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(title, style: pw.TextStyle(font: display, fontSize: 18, color: ink)),
                          pw.SizedBox(height: 3),
                          pw.Text(
                            '${s.valueReportTitle} · ${s.reportDate(date)} · ${s.reportCounts(priced.length, unpriced.length)}',
                            style: small,
                          ),
                          if (container != null && store.pathLabel(container.id).isNotEmpty) ...[
                            pw.SizedBox(height: 2),
                            pw.Text(store.pathLabel(container.id), style: small),
                          ],
                        ],
                      ),
                    ),
                    if (!grand.isEmpty)
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(s.grandTotal, style: small),
                          pw.Text(
                            s.moneyTotals(grand),
                            style: pw.TextStyle(font: display, fontFallback: [body], fontSize: 16, color: ink),
                          ),
                          if (grand.amounts.length > 1) pw.Text(s.currenciesSeparate, style: small.copyWith(fontSize: 7.5)),
                        ],
                      ),
                  ],
                ),
              ),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Envanter', style: small.copyWith(fontSize: 8)),
            pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: small.copyWith(fontSize: 8)),
          ],
        ),
        build: (_) => content,
      ),
    );
    return (title, await doc.save());
  }

  /// Değer dökümünü üretip paylaşma penceresini açar (e-posta, Drive, yazdırma...).
  static Future<void> shareValueReport(BuildContext context, {Node? container}) async {
    final store = InventoryScope.read(context);
    final file = await buildValuePdf(store, container: container);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      text: '${container == null ? '' : '${store.nameOf(container)} - '}${store.strings.valueReportTitle}',
    ));
  }

  /// Koli ve içerik dökümünü CSV formatında üretir (Excel için UTF-8 BOM ile).
  static Future<File> buildCsv(InventoryStore store, Node container) async {
    final s = store.strings;
    final items = collectItems(store, container);
    final buf = StringBuffer();

    // Excel Türkçe karakterleri doğru açsın diye UTF-8 BOM.
    buf.write('\uFEFF');
    if (container.barcode != null) {
      buf.writeln('# ${s.barcode}: ${container.barcode}');
    }

    String escape(String text) {
      if (text.contains(',') || text.contains('"') || text.contains('\n') || text.contains(';')) {
        return '"${text.replaceAll('"', '""')}"';
      }
      return text;
    }

    // Başlık satırı
    buf.writeln([
      escape(s.itemIndexCol),
      escape(s.itemNameCol),
      escape(s.itemQuantityCol),
      escape(s.unit),
      escape(s.itemLocationCol),
      escape(s.itemNoteCol),
      escape(s.itemBarcodeCol),
      escape(s.colUnitPrice),
      escape(s.colAmount),
      escape(s.currency),
      escape(s.colSerial),
    ].join(';'));

    // Tutarlar sayı olarak (binlik ayırıcısız, dilin ondalık işaretiyle): tablo programı
    // toplayabilsin. Birim ayrı sütunda.
    final turkish = s.locale.languageCode == 'tr';

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final name = store.nameOf(item);
      final qty = item.tracksQuantity ? '${item.quantity ?? 1}' : '';
      final unit = item.unit ?? '';
      final relPath = store.pathLabelForParent(item.parentId, inDrawer: item.inDrawer);
      final note = item.note?.trim() ?? '';
      final barcode = item.barcode ?? '';
      final price = item.isContainer ? null : item.priceMoney;

      buf.writeln([
        '${i + 1}',
        escape(name),
        escape(qty),
        escape(unit),
        escape(relPath),
        escape(note),
        escape(barcode),
        escape(price?.inputText(turkish: turkish) ?? ''),
        escape(price == null ? '' : item.value!.inputText(turkish: turkish)),
        escape(price?.currency ?? ''),
        escape(item.isContainer ? '' : item.serial ?? ''),
      ].join(';'));
    }

    final dir = await getTemporaryDirectory();
    final safeName = store.nameOf(container).replaceAll(RegExp(r'[^\w\s\.-]'), '_').trim();
    final file = File(p.join(dir.path, '${safeName}_icerik_dokumu.csv'));
    await file.writeAsString(buf.toString(), flush: true);
    return file;
  }

  /// Kullanıcıya PDF veya CSV seçeneklerini sunan alt sayfa.
  static Future<void> showExportSheet(BuildContext context, Node container) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final choice = await showAppSheet<String>(context, (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  '${store.nameOf(container)} · ${s.exportContent}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent),
                title: Text(s.exportPdfList),
                subtitle: Text(s.boxContentList),
                onTap: () => Navigator.of(sheetContext).pop('pdf'),
              ),
              ListTile(
                leading: const Icon(Icons.table_chart_rounded, color: Colors.green),
                title: Text(s.exportCsvList),
                subtitle: const Text('Excel / CSV'),
                onTap: () => Navigator.of(sheetContext).pop('csv'),
              ),
              // Sigorta, taşınma: içindekilerin değeri yer yer ve toplamıyla.
              ListTile(
                leading: const Icon(Icons.sell_outlined, color: Colors.orange),
                title: Text(s.valueReport),
                subtitle: Text(s.valueReportHint),
                onTap: () => Navigator.of(sheetContext).pop('value'),
              ),
            ],
          ),
        ),
      );
    });

    if (choice == null || !context.mounted) return;

    if (choice == 'pdf') {
      final file = await buildPdf(store, container);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        text: '${store.nameOf(container)} - ${s.boxContentList}',
      ));
    } else if (choice == 'value') {
      await shareValueReport(context, container: container);
    } else if (choice == 'csv') {
      final file = await buildCsv(store, container);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        text: '${store.nameOf(container)} - ${s.boxContentList}',
      ));
    }
  }
}
