import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../core/transitions.dart';
import '../data/node.dart';
import '../services/label_sheet.dart';
import '../services/qr_service.dart';
import '../state/inventory_store.dart';

/// Toplu QR etiketi: bir A4 sayfaya dizilmiş, yazdırılıp kesilecek etiketler.
/// Tek tek QR paylaşmak kutusu çok olan birine yetmiyordu.
class LabelFlows {
  /// Seçilen kayıtların etiketleri (toplu seçimden).
  static Future<void> forNodes(BuildContext context, List<Node> nodes) =>
      showAppSheet<void>(context, (_) => _LabelSheetPanel(nodes: nodes));

  /// Klasörün ⋮ menüsünden: klasörün kendisi ve içindeki klasörler; istenirse
  /// eşyalar da.
  static Future<void> forFolder(BuildContext context, Node folder) =>
      showAppSheet<void>(context, (_) => _LabelSheetPanel(folder: folder));

  /// Klasör ve alt ağacı, destedeki sırayla (derinlik önce).
  static List<Node> subtreeOf(InventoryStore store, Node folder, {required bool items}) {
    final out = <Node>[folder];
    void walk(String id) {
      for (final c in store.childrenOf(id)) {
        if (c.isContainer || items) out.add(c);
        if (c.isContainer) walk(c.id);
      }
    }

    walk(folder.id);
    return out;
  }

  /// Uygulamanın yazı tipleri: PDF'in yerleşik yazı tiplerinde Türkçe harfler yok.
  static Future<(pw.Font, pw.Font)> _fonts() async => (
        pw.Font.ttf(await rootBundle.load('assets/fonts/Fraunces-SemiBold.ttf')),
        pw.Font.ttf(await rootBundle.load('assets/fonts/Manrope-SemiBold.ttf')),
      );

  static Future<File> writePdf(
    InventoryStore store,
    List<Node> nodes, {
    required LabelSize size,
    required String fileName,
  }) async {
    final (display, body) = await _fonts();
    final bytes = await LabelSheet.build(
      [
        for (final n in nodes)
          LabelEntry(
            payload: QrService.payloadFor(n),
            title: store.nameOf(n),
            caption: store.pathLabel(n.id),
            color: canonicalCardColor(n.color).toARGB32(),
          ),
      ],
      size: size,
      display: display,
      body: body,
      title: store.strings.labelsShareText,
    );
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$fileName.pdf'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

class _LabelSheetPanel extends StatefulWidget {
  const _LabelSheetPanel({this.nodes, this.folder});

  final List<Node>? nodes;
  final Node? folder;

  @override
  State<_LabelSheetPanel> createState() => _LabelSheetPanelState();
}

class _LabelSheetPanelState extends State<_LabelSheetPanel> {
  LabelSize _size = LabelSize.medium;

  /// Klasörden açıldıysa: eşyalar da mı (yoksa yalnızca klasörler).
  bool _items = false;
  bool _busy = false;

  List<Node> _nodes(InventoryStore store) =>
      widget.nodes ?? LabelFlows.subtreeOf(store, widget.folder!, items: _items);

  Future<void> _create() async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final nodes = _nodes(store);
    setState(() => _busy = true);
    try {
      final name = widget.folder == null ? '' : '_${QrService.safeFileName(store.nameOf(widget.folder!))}';
      final file = await LabelFlows.writePdf(store, nodes, size: _size, fileName: 'envanter_etiketler$name');
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], text: s.labelsShareText),
      );
      if (navigator.mounted) navigator.pop();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.labelsFailed('$e'))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final count = _nodes(store).length;
    final pages = _size.pagesFor(count);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: tones.line, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Text(s.labelsTitle, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(s.labelsHint, style: theme.textTheme.bodySmall),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sayfanın küçük hali: etiket boyu bir bakışta anlaşılsın.
                SizedBox(width: 104, child: _PagePreview(size: _size, filled: count)),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Caption(s.upper(s.labelSize)),
                      for (final (size, label) in [
                        (LabelSize.small, s.labelSmall),
                        (LabelSize.medium, s.labelMedium),
                        (LabelSize.large, s.labelLarge),
                      ])
                        _Option(
                          selected: _size == size,
                          label: label,
                          detail: s.perPage(size.perPage),
                          onTap: () => setState(() => _size = size),
                        ),
                      if (widget.folder != null) ...[
                        const SizedBox(height: 10),
                        _Caption(s.upper(s.labelsWhich)),
                        _Option(
                          selected: !_items,
                          label: s.labelScopeFolders,
                          onTap: () => setState(() => _items = false),
                        ),
                        _Option(
                          selected: _items,
                          label: s.labelScopeAll,
                          onTap: () => setState(() => _items = true),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              s.labelCount(count, pages),
              textAlign: TextAlign.center,
              style: TextStyle(color: tones.muted, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy || count == 0 ? null : _create,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_rounded),
              label: Text(_busy ? s.preparing : s.createPdf),
            ),
          ],
        ),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Text(
          text,
          style: TextStyle(
            color: Tones.of(context).muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
      );
}

/// Seçenek satırı: solda yuvarlak işaret, adı ve soluk ayrıntısı.
class _Option extends StatelessWidget {
  const _Option({required this.selected, required this.label, required this.onTap, this.detail});

  final bool selected;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? tones.accent : tones.faint,
            ),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: tones.ink)),
            if (detail != null) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: tones.muted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A4 sayfanın küçültülmüş hali: ızgara ve ilk sayfaya düşen etiketler.
class _PagePreview extends StatelessWidget {
  const _PagePreview({required this.size, required this.filled});

  final LabelSize size;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return AspectRatio(
      aspectRatio: 210 / 297,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          // Kağıt her temada beyaz: yazdırılacak olan bu.
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: tones.line),
          boxShadow: [BoxShadow(color: tones.shadow.withValues(alpha: 0.14), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            for (var r = 0; r < size.rows; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var c = 0; c < size.columns; c++)
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(0.8),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFDDD7CC), width: 0.6)),
                          child: r * size.columns + c < filled
                              ? const FittedBox(child: Icon(Icons.qr_code_2_rounded, color: kInk))
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
