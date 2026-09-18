import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../data/node.dart';
import '../state/inventory_host.dart';
import '../state/inventory_store.dart';
import 'actions.dart';
import 'sharing/sharing_flows.dart';
import 'sharing/sharing_scope.dart';
import 'shell.dart';
import 'widgets/date_fields.dart';
import 'widgets/focus_overlay.dart';
import 'widgets/ink_art.dart';
import 'widgets/paper.dart';
import 'widgets/text_prompt.dart';

/// Alışveriş listesi. Kullanıcının ekledikleri (kartın ⋯ menüsünden, önerilerden
/// ya da adet azalınca çıkan bildirimden); eşyada "listeye kendiliğinden ekle"
/// açıksa tükenen, azalan ve tarihi geçenler de. Kapalıyken onlar "Önerilenler"de
/// durur. Markette "Aldım" yalnızca işaretler (her biri için adet ve tarih
/// girmek yoruyordu); adet ve tarih evde "Yerleştirilecek"te girilir. Ortak
/// listede "Alıyorum" denir, ötekiler kimin aldığını görür. Öteki envanterlerin
/// listeleri de altta. Metin olarak paylaşılır (market listesi).
class ShoppingPage extends StatelessWidget {
  const ShoppingPage({super.key});

  /// Paylaşılan metin: başlık, altında listedekiler (öneriler değil).
  static String textOf(InventoryStore store, [DateTime? today]) {
    final s = store.strings;
    return [
      s.shoppingHeader(s.formatDate(today ?? DateTime.now())),
      for (final n in store.shoppingItems)
        switch (store.shoppingReason(n, today)) {
          ShoppingReason.low => '• ${store.nameOf(n)} (${s.lowNote(n.quantity!)})',
          ShoppingReason.expired => '• ${store.nameOf(n)} (${s.pastDateNote})',
          _ => '• ${store.nameOf(n)}',
        },
    ].join('\n');
  }

  /// Markette "Aldım": adet ya da tarih girilecekse "Yerleştirilecek"e geçer,
  /// sorulmaz; öteki (adetsiz, tarihsiz) listeden düşer. Geri alınabilir.
  Future<void> _tick(BuildContext context, Node n) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    if (!n.tracksQuantity && store.shoppingReason(n) != ShoppingReason.expired) return _buy(context, n);
    await store.markBought(n.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.inCart(store.nameOf(n))),
      action: SnackBarAction(label: s.undo, onPressed: () => store.undoBought(n)),
      persist: false,
      duration: const Duration(seconds: 4),
    ));
  }

  /// "Yerleştir" (ya da adetsiz eşyada "Aldım"): adet tutulanda kaç tane alındığı
  /// (tarihliyse yenilerin tarihi) sorulur; hepsinin tarihi geçmişse eskiler
  /// atılır, yenileri girer. Adetsiz tarihi geçende yenisi; ötekinde yalnızca
  /// listeden düşer. Geri alınabilir.
  Future<void> _buy(BuildContext context, Node n) async {
    final store = InventoryScope.read(context);
    final expired = store.shoppingReason(n) == ShoppingReason.expired;
    if (n.tracksQuantity) return _restock(context, n, replace: expired);
    if (expired) return _replace(context, n);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    await store.bought(n.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.removedFromShopping(store.nameOf(n))),
      action: SnackBarAction(label: s.undo, onPressed: () => store.undoBought(n)),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _restock(BuildContext context, Node n, {bool replace = false}) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final values = await showTextPrompt(
      context,
      title: store.nameOf(n),
      message: s.howManyBought,
      fields: [
        PromptField(
          label: s.quantity,
          // Hepsi bozulmuşsa kaç tane atılıyorsa o kadar yenisi alınmış olabilir.
          initial: replace ? '${n.quantity ?? 1}' : '1',
          keyboardType: TextInputType.number,
          selectAll: true,
        ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.bought,
    );
    final count = int.tryParse(values?.single.trim() ?? '');
    if (count == null || count <= 0 || !context.mounted) return;
    // Tarihli eşyada yenilerin tarihi farklı olabilir: ayrı paket. Raf ömrü
    // varsa bugünden hesaplanır; vazgeçilirse en yeni paketin tarihini alır.
    DateTime? expires;
    if (n.shelfLife == null && n.lastExpiry != null) {
      expires = await pickDay(context, initial: replace ? null : n.lastExpiry, help: s.newLotsDate);
    }
    if (replace) {
      await store.replaceExpired(n.id, count, expires: expires);
    } else {
      await store.restock(n.id, count, expires: expires);
    }
    final now = store.byId(n.id)?.quantity ?? count;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.restocked(store.nameOf(n), now)),
      action: SnackBarAction(label: s.undo, onPressed: () => store.undoBought(n)),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _replace(BuildContext context, Node n) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    await store.replaced(n.id);
    if (!context.mounted) return;
    final fresh = store.byId(n.id) ?? n;
    final next = fresh.effectiveExpiry;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(next != null
          ? s.replacedWithDate(store.nameOf(fresh), s.formatDate(next))
          : s.replacedEnterDate(store.nameOf(fresh))),
      // Paketteki yeni tarih girilmeli; düzenleyici tek dokunuş ötede.
      action: next != null ? null : SnackBarAction(label: s.enterDate, onPressed: () => NodeActions.edit(context, fresh)),
      persist: false,
      duration: const Duration(seconds: 6),
    ));
  }

  Future<void> _remove(BuildContext context, Node n) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    await store.setWanted(n.id, false);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.removedFromShopping(store.nameOf(n))),
      action: SnackBarAction(label: s.undo, onPressed: () => store.setWanted(n.id, true)),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final items = store.shoppingItems;
    final suggestions = store.shoppingSuggestions;
    final putAway = store.toPutAway;
    // "Alıyorum" yalnızca başkalarıyla paylaşılan listede anlamlı.
    final sharing = SharingScope.maybeOf(context);
    final shared = sharing?.config.isShared ?? false;
    final now = DateTime.now();
    String who(String id) => id == store.authorId ? s.you : sharing?.memberName(id) ?? s.user;
    // Öteki envanterlerin listeleri (kapanırken saklanan).
    final host = LibraryScope.maybeOf(context);
    final others = [
      if (host != null)
        for (final e in host.library.entries)
          if (e.id != host.library.activeId && e.shopping.isNotEmpty) e,
    ];

    /// Neden alınmalı ve nerede: "Tükendi · Mutfak", "2 kaldı · en az 3 · Mutfak"...
    String reason(Node n) => switch (store.shoppingReason(n)) {
          ShoppingReason.out => '${s.outOfStock} · ${store.pathLabel(n.id)}',
          ShoppingReason.low => '${s.lowLeft(n.quantity!, n.minQuantity!)} · ${store.pathLabel(n.id)}',
          ShoppingReason.expired =>
            '${s.expiryOn(s.formatDate(n.effectiveExpiry!))} · ${dueText(s, n.effectiveExpiry!)}',
          null => store.pathLabel(n.id),
        };

    /// Biri "alıyorum" dediyse o da.
    String detail(Node n) => [
          reason(n),
          if (shared)
            if (n.buyingNow(now) case final by?) by == store.authorId ? s.youAreBuying : s.isBuying(who(by)),
        ].join(' · ');

    Widget tile(Node n, {required Widget action, Widget? extra, String? subtitle}) => RecordTile(
          node: n,
          title: store.nameOf(n),
          subtitle: subtitle ?? detail(n),
          onTap: () => showNodeFocus(context, n),
          trailing: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [?extra, action]),
          ),
        );

    Widget button(String label, VoidCallback onPressed) => FilledButton.tonal(
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: onPressed,
          child: Text(label),
        );

    List<Widget> section(String title, List<Widget> tiles, {String? hint}) => [
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 18, bottom: 8),
            child: Text(
              s.upper(title),
              style: TextStyle(color: tones.muted, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1),
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 10),
              child: Text(hint, style: theme.textTheme.bodySmall),
            ),
          for (final (i, t) in tiles.indexed) ...[
            if (i > 0) const SizedBox(height: 10),
            t,
          ],
        ];

    return Scaffold(
      appBar: ShellHeader(
        title: s.shoppingList,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: s.shareList,
              icon: const Icon(Icons.ios_share_rounded),
              onPressed: () => SharePlus.instance.share(ShareParams(text: textOf(store))),
            ),
        ],
      ),
      body: items.isEmpty && suggestions.isEmpty && putAway.isEmpty && others.isEmpty
          ? EmptyState(art: InkArtKind.done, title: s.shoppingEmpty, body: s.shoppingEmptyHint)
          : ListView(
              padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 0, 16, 32)),
              children: [
                if (items.isNotEmpty)
                  ...section(s.toBuySection, [
                    for (final n in items)
                      tile(
                        n,
                        extra: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Ortak listede: "ben alıyorum", ötekiler görsün.
                            if (shared)
                              IconButton(
                                tooltip: n.buyingNow(now) == store.authorId ? s.notBuying : s.imBuying,
                                isSelected: n.buyingNow(now) == store.authorId,
                                icon: const Icon(Icons.front_hand_outlined),
                                selectedIcon: Icon(Icons.front_hand_rounded, color: tones.accent),
                                onPressed: () => store.setBuying(n.id, n.buyingNow(now) != store.authorId),
                              ),
                            // Elle eklenen listeden çıkarılabilir; otomatik girenler
                            // alınınca ya da durumu düzelince kendiliğinden düşer.
                            if (n.isWanted)
                              IconButton(
                                tooltip: s.removeFromShopping,
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () => _remove(context, n),
                              ),
                          ],
                        ),
                        action: button(
                          store.shoppingReason(n) == ShoppingReason.expired ? s.boughtNew : s.bought,
                          () => _tick(context, n),
                        ),
                      ),
                  ]),
                if (putAway.isNotEmpty)
                  ...section(
                    s.putAwaySection,
                    [
                      for (final n in putAway)
                        tile(
                          n,
                          subtitle: [
                            s.boughtWhen(SharingFlows.ago(context, n.boughtAt!)),
                            store.pathLabel(n.id),
                          ].join(' · '),
                          extra: IconButton(
                            tooltip: s.backToList,
                            icon: const Icon(Icons.undo_rounded),
                            onPressed: () => store.unmarkBought(n.id),
                          ),
                          action: button(s.putAway, () => _buy(context, n)),
                        ),
                    ],
                    hint: s.putAwayHint,
                  ),
                if (suggestions.isNotEmpty)
                  ...section(
                    s.suggestionsSection,
                    [
                      for (final n in suggestions)
                        tile(n, action: button(s.addShort, () => store.setWanted(n.id, true))),
                    ],
                    hint: s.suggestionsHint,
                  ),
                // Öteki envanterlerin listeleri: dokununca o envantere geçilir.
                if (others.isNotEmpty)
                  ...section(
                    s.otherListsSection,
                    [
                      for (final e in others)
                        Material(
                          color: tones.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => host.openAt(e.id, Arrival(e.id, shopping: true)),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: tones.line),
                              ),
                              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(host!.nameOf(e, s), style: theme.textTheme.titleMedium),
                                        const SizedBox(height: 4),
                                        for (final x in e.shopping)
                                          Text(
                                            x.note.isEmpty ? '• ${x.name}' : '• ${x.name} (${x.note})',
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.swap_horiz_rounded, color: tones.muted),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                    hint: s.otherListsHint,
                  ),
              ],
            ),
    );
  }
}
