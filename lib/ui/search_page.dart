import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/text_match.dart';
import '../data/node.dart';
import '../services/qr_service.dart';
import '../data/library.dart';
import '../state/inventory_host.dart';
import '../state/inventory_store.dart';
import '../core/transitions.dart';
import 'actions.dart';
import 'container_screen.dart';
import 'scan_page.dart';
import 'visual_search_page.dart';
import 'widgets/focus_overlay.dart';
import '../core/theme.dart';
import 'widgets/paper.dart';
import 'widgets/ink_art.dart';
import 'shell.dart';
import '../core/palette.dart';

/// QR ya da ürün barkodu okutur. Klasör kodu içini açar; eşya kodu klasörü
/// açmadan kartın kendisini öne çıkarır; barkod, onu taşıyan eşyayı bulur.
/// Arama sayfasından da alt çubuktan da. [parentId]: barkod kayıtlı değilse
/// yeni eşyanın başlayacağı seviye (alt çubukta açık olan seviye).
/// Aynı anda tek tarayıcı: hızlı iki dokunuş iki kamera ekranı açarsa
/// ikincisi "kamera zaten çalışıyor" diye hata verirdi.
bool _scanning = false;

Future<void> scanQrAndOpen(BuildContext context, {String? parentId}) async {
  if (_scanning) return;
  final navigator = Navigator.of(context);

  _scanning = true;
  final ScannedCode? code;
  try {
    code = await navigator.push<ScannedCode>(
      MaterialPageRoute(builder: (_) => const ScanPage(serialCount: true)),
    );
  } finally {
    _scanning = false;
  }
  if (code == null || !context.mounted) return;
  await openScanned(context, code, parentId: parentId);
}

Future<void> _openRecord(BuildContext context, Node node) async {
  if (node.isContainer) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContainerScreen(containerId: node.id)),
    );
  } else {
    await showNodeFocus(context, node);
  }
}

/// Okunan kodun gereğini yapar (tarayıcıdan ayrı: kamerasız da sınanabilsin).
Future<void> openScanned(BuildContext context, ScannedCode code, {String? parentId}) async {
  final store = InventoryScope.read(context);
  final s = store.strings;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  if (code.barcode case final barcode?) {
    final matches = store.byBarcode(barcode);
    if (matches.length == 1) return _openRecord(context, matches.single);
    if (matches.length > 1) {
      // Aynı üründen iki yerde: hangisi olduğu sorulur.
      final picked = await showAppSheet<Node>(context, (_) => _BarcodeMatches(barcode: barcode, matches: matches));
      if (picked != null && context.mounted) await _openRecord(context, picked);
      return;
    }
    // Başka bir envanterde kayıtlıysa oraya geçilir (QR etiketindeki gibi).
    final host = LibraryScope.read(context);
    final hit = host?.findBarcodeInOthers(barcode);
    if (host != null && hit != null) {
      messenger.showSnackBar(SnackBar(content: Text(s.switchedTo(host.nameOf(hit.entry, s)))));
      await host.openAt(hit.entry.id, Arrival(hit.entry.id, recordId: hit.record.id, inside: hit.record.container));
      return;
    }
    // Hiçbir yerde yok: bu barkodla yeni eşya ya da klasör önerilir.
    final kind = await showDialog<NodeKind>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.barcodeUnknown),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(barcode, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
            const SizedBox(height: 10),
            Text(s.barcodeUnknownBody),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(NodeKind.container),
            child: Text(s.newContainerWithBarcode),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(NodeKind.item),
            child: Text(s.newItemWithBarcode),
          ),
        ],
      ),
    );
    if (kind != null && context.mounted) {
      await NodeActions.create(context, parentId: parentId ?? Roots.home, kind: kind, barcode: barcode);
    }
    return;
  }

  final node = store.byId(code.id);
  // Çöpteki bir klasörün içindeki kayıt da açılmaz (çöp işareti yalnızca klasörün kendisinde).
  if (node == null || !store.isLive(node)) {
    // Başka bir envanterin etiketi: o envantere geçilip kayıt gösterilir.
    final host = LibraryScope.read(context);
    final entry = node == null ? host?.findInOthers(code.id) : null;
    if (host != null && entry != null) {
      messenger.showSnackBar(SnackBar(content: Text(s.switchedTo(host.nameOf(entry, s)))));
      await host.openAt(entry.id, Arrival(entry.id, recordId: code.id, inside: true));
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text(s.qrRecordMissing)));
    return;
  }
  if (node.isContainer) {
    await navigator.push(
      MaterialPageRoute(builder: (_) => ContainerScreen(containerId: node.id)),
    );
  } else {
    if (!context.mounted) return;
    await showNodeFocus(context, node);
  }
}

/// Aynı barkodu taşıyan birden çok kayıt: yerleriyle listelenir, biri seçilir.
class _BarcodeMatches extends StatelessWidget {
  const _BarcodeMatches({required this.barcode, required this.matches});

  final String barcode;
  final List<Node> matches;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 2),
            child: Text(s.barcodeMatches(matches.length), style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
            child: Text(barcode, style: theme.textTheme.bodySmall),
          ),
          for (final node in matches) ...[
            RecordTile(
              node: node,
              title: store.nameOf(node),
              subtitle: [
                store.pathLabel(node.id),
                if (node.tracksQuantity) node.quantity == 0 ? s.outOfStock : s.quantityShort(node.quantity!),
              ].join(' · '),
              onTap: () => Navigator.of(context).pop(node),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Kaydın bulunduğu klasörü açar ve kartı destede öne getirir (arama ve
/// tarihi yaklaşanlar listesinden "yerine git").
void revealNode(BuildContext context, Node node) {
  final store = InventoryScope.read(context);
  final navigator = Navigator.of(context);
  final chain = store.ancestorsOf(node.id);
  navigator.popUntil((r) => r.isFirst);
  for (var i = 0; i < chain.length; i++) {
    final highlight = i + 1 < chain.length ? chain[i + 1].id : node.id;
    navigator.push(MaterialPageRoute(
      builder: (_) => ContainerScreen(containerId: chain[i].id, highlightId: highlight),
    ));
  }
}

enum _SearchFilter {
  all,
  containers,
  items,
  withDates,
  withPhotos,
  outOfStock,
  withAttachments,
  borrowed,
}

/// Ad, konum adı ve nota göre arama; ayrıca QR okutma ve fotoğrafla arama.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  _SearchFilter _filter = _SearchFilter.all;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _scan() => scanQrAndOpen(context);

  Future<void> _visualSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VisualSearchPage()),
    );
  }

  void _reveal(Node node) => revealNode(context, node);

  Widget _header(String text, Tones tones, {double top = 4}) => Padding(
        padding: EdgeInsets.only(left: 6, top: top, bottom: 6),
        child: Text(
          text,
          style: TextStyle(color: tones.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
        ),
      );

  /// Arama sonucu ya da son dokunulan kayıt satırı. Aranan kelimelerden biri
  /// adda geçmiyorsa (notta ya da konum adında bulunduysa) o parça ikinci
  /// satırda vurgulanır: kaydın neden çıktığı görünsün.
  Widget _tile(InventoryStore store, Node node, List<String> tokens) {
    final s = store.strings;
    final name = foldForSearch(node.trimmedName);
    final outside = [for (final t in tokens) if (!name.contains(t)) t];
    String? detail;
    IconData? detailIcon;
    if (outside.isNotEmpty) {
      final note = node.note ?? '';
      final label = node.locationLabel ?? '';
      if (matchRanges(note, outside).isNotEmpty) {
        detail = '${s.inNote}: ${snippetAround(note, outside)}';
        detailIcon = Icons.sticky_note_2_outlined;
      } else if (matchRanges(label, outside).isNotEmpty) {
        detail = label;
        detailIcon = Icons.place_outlined;
      } else if (node.attachments.where((a) => matchRanges(a.name, outside).isNotEmpty).firstOrNull case final a?) {
        // Ekinin adında bulundu ("kılavuz").
        detail = a.name;
        detailIcon = Icons.attach_file_rounded;
      } else if (node.barcode case final b? when matchRanges(b, outside).isNotEmpty) {
        detail = '${s.barcode}: $b';
        detailIcon = Icons.qr_code_scanner_rounded;
      }
    }
    return RecordTile(
      node: node,
      title: store.nameOf(node),
      highlight: tokens,
      detail: detail,
      detailIcon: detailIcon,
      subtitle: [
        store.pathLabel(node.id),
        if (node.tracksQuantity)
          node.quantity == 0 ? s.outOfStock : s.quantityShort(node.quantity!),
      ].join(' · '),
      onTap: () {
        if (node.isContainer) {
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ContainerScreen(containerId: node.id),
          ));
        } else {
          showNodeFocus(context, node);
        }
      },
      trailing: IconButton(
        icon: const Icon(Icons.my_location_rounded),
        tooltip: s.goToPlace,
        onPressed: () => _reveal(node),
      ),
    );
  }

  /// Açık olmayan bir envanterde bulunan kayıt: dokununca o envantere geçilir,
  /// kayıt yerinde gösterilir.
  Widget _otherTile(InventoryStore store, OtherHit hit, List<String> tokens) {
    final s = store.strings;
    final tones = Tones.of(context);
    final host = LibraryScope.read(context)!;
    final r = hit.record;
    return Material(
      color: tones.surface,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: tones.line)),
        leading: Icon(r.container ? Icons.inventory_2_outlined : Icons.category_outlined, color: tones.muted),
        title: Text.rich(highlightedText(
          r.name,
          tokens,
          marker: tones.accent.withValues(alpha: 0.28),
          style: TextStyle(fontFamily: kDisplayFont, fontSize: 17, fontWeight: FontWeight.w600, color: tones.ink),
        )),
        subtitle: Text(
          [
            host.nameOf(hit.entry, s),
            r.path,
            if (r.quantity case final q?) q == 0 ? s.outOfStock : s.quantityShort(q),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.swap_horiz_rounded),
        onTap: () => host.openAt(hit.entry.id, Arrival(hit.entry.id, recordId: r.id)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final query = _ctrl.text;
    final results = store.search(query);
    final tokens = searchTokens(query);
    // Öteki envanterlerde de (kapanırken yazılan dizinden).
    final host = LibraryScope.maybeOf(context);
    final others = host?.searchOthers(query) ?? const <OtherHit>[];
    final unindexed = query.trim().isEmpty ? const <InventoryEntry>[] : host?.unindexed ?? const <InventoryEntry>[];

    final filteredResults = results.where((n) {
      return switch (_filter) {
        _SearchFilter.all => true,
        _SearchFilter.containers => n.isContainer,
        _SearchFilter.items => !n.isContainer,
        _SearchFilter.withDates => n.hasDates,
        _SearchFilter.withPhotos => n.hasImage,
        _SearchFilter.outOfStock => !n.isContainer && n.quantity == 0,
        _SearchFilter.withAttachments => n.hasAttachments,
        _SearchFilter.borrowed => n.isBorrowed,
      };
    }).toList();
    final filteredOthers = others.where((hit) {
      final r = hit.record;
      return switch (_filter) {
        _SearchFilter.all => true,
        _SearchFilter.containers => r.container,
        _SearchFilter.items => !r.container,
        _SearchFilter.outOfStock => !r.container && r.quantity == 0,
        _ => true,
      };
    }).toList();
    final tones = Tones.of(context);

    return Scaffold(
      appBar: PreferredSize(
        // Yatayda alçak (bkz. ShellHeader.landscape).
        preferredSize: Size.fromHeight(ShellHeader.landscape ? 62 : 78),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: ShellHeader.landscape
                ? const EdgeInsets.fromLTRB(12, 4, 16, 4)
                : const EdgeInsets.fromLTRB(12, 10, 16, 8),
            child: Row(
              children: [
                RoundSlot(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: s.back,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onTapOutside: dismissKeyboard,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: s.searchHint,
                      fillColor: tones.surface,
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(color: tones.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(color: tones.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(color: tones.ink, width: 1.4),
                      ),
                      suffixIcon: query.isEmpty
                          ? IconButton(
                              icon: const Icon(Icons.qr_code_scanner_rounded),
                              tooltip: s.scanQr,
                              onPressed: _scan,
                            )
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: s.clear,
                              onPressed: () => setState(_ctrl.clear),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: query.trim().isEmpty
          ? _Hint(
              strings: s,
              onScan: _scan,
              onVisual: _visualSearch,
              recent: [for (final n in store.recent.take(8)) _tile(store, n, const [])],
            )
          : results.isEmpty && others.isEmpty
              // Sonuç yok: ne denenebileceği ve yazmadan bulmanın iki yolu (eşyanın
              // adı hatırlanmıyorsa etiketi okutulur ya da fotoğrafı çekilir).
              ? EmptyState(
                  art: InkArtKind.search,
                  artSize: 104,
                  title: s.noResultFor(query),
                  body: [
                    s.noResultHint,
                    if (unindexed.isNotEmpty) s.notSearchedYet([for (final e in unindexed) host!.nameOf(e, s)].join(', ')),
                  ].join('\n\n'),
                  action: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _scan,
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        label: Text(s.scanQr),
                      ),
                      OutlinedButton.icon(
                        onPressed: _visualSearch,
                        icon: const Icon(Icons.image_search_rounded, size: 18),
                        label: Text(s.visualSearch),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 4, 16, 24)),
                  children: [
                    // Filtreleme çipleri: Tümü, Klasörler, Eşyalar, Tarihliler, Fotoğraflılar, Tükenenler, Ekler
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          for (final f in _SearchFilter.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(switch (f) {
                                  _SearchFilter.all => s.allFilter,
                                  _SearchFilter.containers => s.foldersOnly,
                                  _SearchFilter.items => s.itemsOnly,
                                  _SearchFilter.withDates => s.withDatesOnly,
                                  _SearchFilter.withPhotos => s.withPhotosOnly,
                                  _SearchFilter.outOfStock => s.outOfStockOnly,
                                  _SearchFilter.withAttachments => s.withAttachmentsOnly,
                                  _SearchFilter.borrowed => s.filterBorrowed,
                                }),
                                selected: _filter == f,
                                onSelected: (_) => setState(() => _filter = f),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (filteredResults.isNotEmpty) ...[
                      _header(s.upper(s.resultCount(filteredResults.length)), tones),
                      for (final (i, n) in filteredResults.indexed) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _tile(store, n, tokens),
                      ],
                    ],
                    if (filteredOthers.isNotEmpty) ...[
                      _header(s.upper(s.inOtherInventories(filteredOthers.length)), tones, top: filteredResults.isEmpty ? 4 : 24),
                      for (final (i, hit) in filteredOthers.indexed) ...[
                        if (i > 0) const SizedBox(height: 10),
                        _otherTile(store, hit, tokens),
                      ],
                    ],
                    if (unindexed.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 18, 6, 0),
                        child: Text(
                          s.notSearchedYet([for (final e in unindexed) host!.nameOf(e, s)].join(', ')),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
    );
  }
}

/// Boş arama: kısa açıklama ve adı hatırlanmayan şeyler için iki kestirme.
/// Bu cihazda son dokunulan kayıtlar varsa açıklamanın yerini onlar alır:
/// "dün bir şey koydum, neredeydi" sorusu çoğu zaman aramaya gerek bırakmaz.
class _Hint extends StatelessWidget {
  const _Hint({
    required this.strings,
    required this.onScan,
    required this.onVisual,
    this.recent = const [],
  });

  final AppStrings strings;
  final VoidCallback onScan;
  final VoidCallback onVisual;
  final List<Widget> recent;

  Widget _shortcuts() => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Shortcut(
                icon: Icons.qr_code_scanner_rounded,
                title: strings.scanQr,
                subtitle: strings.qrShortcutHint,
                color: kCardPalette[2],
                onTap: onScan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Shortcut(
                icon: Icons.image_search_rounded,
                title: strings.visualSearch,
                subtitle: strings.photoShortcutHint,
                color: kCardPalette[8],
                onTap: onVisual,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    if (recent.isNotEmpty) {
      return ListView(
        padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 8, 16, 24)),
        children: [
          _shortcuts(),
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 24, bottom: 8),
            child: Text(
              strings.upper(strings.recentTitle),
              style: TextStyle(color: tones.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
            ),
          ),
          for (final (i, tile) in recent.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            tile,
          ],
        ],
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const InkArt(InkArtKind.search, size: 120),
              const SizedBox(height: 16),
              Text(strings.searchInInventory, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                strings.searchInInventoryHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: Tones.of(context).muted, height: 1.45),
              ),
              const SizedBox(height: 26),
              _shortcuts(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = cardTone(color.toARGB32(), Theme.of(context).brightness);
    final ink = onColorOf(tone);
    return Material(
      color: tone,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: tone, size: 22),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(fontFamily: kDisplayFont, fontSize: 18, fontWeight: FontWeight.w600, color: ink),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 12.5, height: 1.35, color: ink.withValues(alpha: 0.72))),
            ],
          ),
        ),
      ),
    );
  }
}
