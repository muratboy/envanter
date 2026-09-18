import 'package:flutter/material.dart';

import '../core/money.dart';
import '../core/theme.dart';
import '../data/node.dart';
import '../services/box_export.dart';
import '../state/inventory_store.dart';
import 'actions.dart';
import 'shell.dart';
import 'widgets/focus_overlay.dart';
import 'widgets/ink_art.dart';
import 'widgets/paper.dart';

/// Envanterin değeri: toplam, yerlere (en üstteki klasörlere) göre dağılım, en değerli
/// eşyalar ve fiyatı olmayanlar. Sigorta ve taşınma için PDF dökümü buradan alınır. Sol
/// menüden açılır. Kur çevrimi yok: her para birimi ayrı toplanır.
class ValuePage extends StatelessWidget {
  const ValuePage({super.key});

  /// "En değerliler"de gösterilen eşya sayısı.
  static const shown = 10;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final total = store.totalValue;
    final ranking = store.valueRanking;
    final main = total.mainCurrency;

    // Yerler: ana ekrandaki her klasör, ana ekranda tek duran eşyalar, çekmece ve kayıplar.
    final places = <(String, Node?, MoneyTotals)>[];
    final loose = MoneyTotals();
    for (final c in store.childrenOf(Roots.home)) {
      if (c.isContainer) {
        final v = store.valueOf(c.id);
        if (!v.isEmpty) places.add((store.nameOf(c), c, v));
      } else if (c.value case final v?) {
        loose.add(v);
      }
    }
    if (!loose.isEmpty) places.add((s.home, null, loose));
    for (final (label, root) in [(s.drawer, Roots.drawer), (s.lostItems, Roots.lost)]) {
      final v = store.valueOf(root);
      if (!v.isEmpty) places.add((label, null, v));
    }
    places.sort((a, b) => b.$3.centsIn(main ?? '').compareTo(a.$3.centsIn(main ?? '')));

    String valueLine(Node n) {
      final q = n.quantity;
      return q == null || q == 1
          ? s.money(n.value!)
          : s.valueTimes(q, s.money(n.priceMoney!), s.money(n.value!));
    }

    Widget heading(String title) => Padding(
          padding: const EdgeInsets.only(left: 6, top: 18, bottom: 8),
          child: Text(
            s.upper(title),
            style: TextStyle(color: tones.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
          ),
        );

    return Scaffold(
      appBar: ShellHeader(
        title: s.valuePageTitle,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ranking.priced.isEmpty
          ? EmptyState(art: InkArtKind.box, title: s.noValueYet, body: s.noValueHint)
          : ListView(
              padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 0, 16, 32)),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: tones.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: tones.line),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.totalValue, style: theme.textTheme.labelLarge?.copyWith(color: tones.muted)),
                      const SizedBox(height: 4),
                      // Birden çok birim alt alta: "12.500 ₺" / "300 $" (toplanamazlar).
                      for (final m in total.amounts)
                        Text(s.money(m), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        s.reportCounts(ranking.priced.length, ranking.unpriced.length),
                        style: theme.textTheme.bodySmall?.copyWith(color: tones.muted),
                      ),
                      if (total.amounts.length > 1)
                        Text(s.currenciesSeparate, style: theme.textTheme.bodySmall?.copyWith(color: tones.muted)),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: Text(s.valueReport),
                        onPressed: () => BoxExportService.shareValueReport(context),
                      ),
                    ],
                  ),
                ),
                if (ranking.unpriced.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  PaperSection(
                    padding: EdgeInsets.zero,
                    children: [
                      PaperRow(
                        icon: Icons.sell_outlined,
                        tint: tones.lost,
                        title: s.unpricedItems(ranking.unpriced.length),
                        subtitle: s.unpricedHint,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const _UnpricedPage()),
                        ),
                      ),
                    ],
                  ),
                ],
                heading(s.valueByPlace),
                PaperSection(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final (label, node, value) in places)
                      PaperRow(
                        icon: node == null ? Icons.inbox_outlined : Icons.folder_outlined,
                        title: label,
                        subtitle: s.moneyTotals(value),
                        onTap: node == null ? null : () => showNodeFocus(context, node),
                      ),
                  ],
                ),
                heading(s.mostValuable),
                for (final (i, n) in ranking.priced.take(shown).indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  RecordTile(
                    node: n,
                    title: store.nameOf(n),
                    subtitle: valueLine(n),
                    detail: store.pathLabel(n.id),
                    detailIcon: Icons.place_outlined,
                    onTap: () => showNodeFocus(context, n),
                  ),
                ],
              ],
            ),
    );
  }
}

/// Fiyatı girilmemiş eşyalar; dokununca düzenleyici açılır (fiyat orada yazılır).
class _UnpricedPage extends StatelessWidget {
  const _UnpricedPage();

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final unpriced = store.valueRanking.unpriced;
    return Scaffold(
      appBar: ShellHeader(
        title: s.unpricedSection,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: unpriced.isEmpty
          ? EmptyState(art: InkArtKind.box, title: s.unpricedSection)
          : ListView.separated(
              padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 8, 16, 32)),
              itemCount: unpriced.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final n = unpriced[i];
                return RecordTile(
                  node: n,
                  title: store.nameOf(n),
                  subtitle: store.pathLabel(n.id),
                  onTap: () => NodeActions.edit(context, n),
                );
              },
            ),
    );
  }
}
