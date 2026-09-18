import 'package:flutter/material.dart';

import '../../data/node.dart';
import '../../state/inventory_store.dart';
import '../actions.dart';
import '../../core/theme.dart';
import '../node_list_view.dart';
import '../shell.dart';
import 'ink_art.dart';
import 'tree_picker.dart';

/// Sağdan açılan panellerden hangisi.
enum PanelKind {
  /// Yeri henüz belli olmayanlar.
  drawer,

  /// Yerinde bulunamayanlar.
  lost,

  /// Sık kullanılanlar: ağacın neresinde olursa olsun kısayol.
  favorites,

  /// Son kullanma tarihi geçip hâlâ yerinde duranlar: sık kullanılanlar gibi
  /// yalnızca bir işaret listesi; bırakma kabul etmez.
  expired,
}

/// Sağdan açılan panelin içeriği. Çekmece ve kayıp çekmecesi ağacın birer
/// kökü; sık kullanılanlar ise ağacın her yerinden toplanmış bir kısayol
/// listesidir. Sürüklenen kart doğrudan panele bırakılabilir (çekmeceye /
/// kayıba taşır, sık kullanılanlara ekler); buradaki bir kart sürüklenmeye
/// başlayınca panel kenara çekilir ve kart arkadaki desteye taşınabilir.
class UnsortedDrawerBody extends StatelessWidget {
  const UnsortedDrawerBody({super.key, required this.onClose, this.kind = PanelKind.drawer});

  final VoidCallback onClose;
  final PanelKind kind;

  bool get _isLost => kind == PanelKind.lost;

  /// Sık kullanılanlar ve tarihi geçenler bir kök değil; ötekiler ağacın köklerinden biri.
  String? get _bucket => switch (kind) {
        PanelKind.drawer => Roots.drawer,
        PanelKind.lost => Roots.lost,
        PanelKind.favorites || PanelKind.expired => null,
      };

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final bucket = _bucket;
    final items = switch (kind) {
      PanelKind.favorites => store.favorites,
      PanelKind.expired => store.expiredItems,
      _ => store.childrenOf(bucket!),
    };
    final tones = Tones.of(context);

    final title = switch (kind) {
      PanelKind.drawer => s.drawer,
      PanelKind.lost => s.lostDrawer,
      PanelKind.favorites => s.favorites,
      PanelKind.expired => s.expiredPanel,
    };
    final eyebrow = switch (kind) {
      PanelKind.drawer => items.isEmpty ? s.drawerSubtitle : s.drawerWaiting(items.length),
      PanelKind.lost => items.isEmpty ? s.lostSubtitle : s.lostWaiting(items.length),
      PanelKind.favorites => items.isEmpty ? s.favoritesSubtitle : s.recordCount(items.length),
      PanelKind.expired => items.isEmpty ? s.expiredSubtitle : s.recordCount(items.length),
    };

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => switch (kind) {
        PanelKind.expired => false,
        PanelKind.favorites => !store.isFavorite(details.data),
        _ => store.canMove(details.data, bucket!),
      },
      onAcceptWithDetails: (details) async {
        final node = store.byId(details.data);
        final messenger = ScaffoldMessenger.of(context);
        store.setDragging(null);
        if (node == null) return;
        // Klasör çekmeceye bırakıldı: kendisi mi gitsin, içindekiler mi?
        if (bucket == Roots.drawer && node.isContainer) {
          await NodeActions.dropFolder(context, folder: node, targetId: Roots.drawer);
          return;
        }
        if (bucket == null) {
          await store.toggleFavorite(details.data);
        } else {
          if (!await store.move(details.data, bucket)) return;
          // Çekmeceye ya da kayıp çekmecesine bırakılan eski yerine dönebilir.
          NodeActions.movedNotice(
            messenger,
            store,
            [node],
            kind == PanelKind.lost ? s.markedLost(store.nameOf(node)) : s.movedToDrawer(store.nameOf(node)),
          );
          return;
        }
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(switch (kind) {
            PanelKind.drawer => s.movedToDrawer(store.nameOf(node)),
            PanelKind.lost => s.markedLost(store.nameOf(node)),
            PanelKind.favorites || PanelKind.expired => s.favoriteAdded(store.nameOf(node)),
          }),
          duration: const Duration(seconds: 2),
        ));
      },
      builder: (context, candidate, _) => ColoredBox(
        color: candidate.isEmpty
            ? tones.surface
            : Color.alphaBlend(tones.accent.withValues(alpha: 0.10), tones.surface),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    RoundSlot(
                      child: IconButton(
                        icon: const Icon(Icons.chevron_right_rounded),
                        tooltip: s.close,
                        onPressed: onClose,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.upper(eyebrow),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _isLost ? tones.lost : tones.muted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.headlineMedium?.copyWith(fontSize: 26),
                          ),
                        ],
                      ),
                    ),
                    if (kind == PanelKind.drawer) ...[
                      if (items.isNotEmpty) ...[
                        RoundSlot(
                          child: IconButton(
                            tooltip: s.quickMove,
                            icon: const Icon(Icons.drive_file_move_outline),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final target = await pickTreeTargetForMany(context, items);
                              if (target == null || !context.mounted) return;
                              final moved = await store.moveMany([for (final n in items) n.id], target);
                              if (!context.mounted) return;
                              if (moved.isEmpty) {
                                messenger.showSnackBar(SnackBar(content: Text(s.moveNotPossible)));
                                return;
                              }
                              NodeActions.movedNotice(
                                messenger,
                                store,
                                moved,
                                s.movedTo(s.recordCount(moved.length), store.pathLabel(target)),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      RoundSlot(
                        child: IconButton(
                          tooltip: s.newRecordToDrawer,
                          icon: const Icon(Icons.add_rounded),
                          onPressed: () => NodeActions.create(
                            context,
                            parentId: Roots.drawer,
                            kind: NodeKind.item,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? _EmptyHint(kind: kind)
                    : NodeListView(
                        // Sık kullanılanlar bir seviye değil: kayıtlar
                        // doğrudan verilir, alt yazıda yerleri yazar.
                        parentId: bucket ?? Roots.home,
                        source: switch (kind) {
                          PanelKind.favorites => (store) => store.favorites,
                          PanelKind.expired => (store) => store.expiredItems,
                          _ => null,
                        },
                        compact: true,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.kind});

  final PanelKind kind;

  @override
  Widget build(BuildContext context) {
    final s = InventoryScope.of(context).strings;
    return EmptyState(
      art: switch (kind) {
        PanelKind.drawer => InkArtKind.drawer,
        PanelKind.lost => InkArtKind.lost,
        PanelKind.favorites => InkArtKind.star,
        PanelKind.expired => InkArtKind.done,
      },
      artSize: 112,
      title: switch (kind) {
        PanelKind.drawer => s.drawerEmpty,
        PanelKind.lost => s.lostEmpty,
        PanelKind.favorites => s.favoritesEmpty,
        PanelKind.expired => s.expiredEmpty,
      },
      body: switch (kind) {
        PanelKind.drawer => s.drawerEmptyHint,
        PanelKind.lost => s.lostEmptyHint,
        PanelKind.favorites => s.favoritesEmptyHint,
        PanelKind.expired => s.expiredEmptyHint,
      },
    );
  }
}
