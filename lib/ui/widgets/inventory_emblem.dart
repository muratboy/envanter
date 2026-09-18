import 'package:flutter/material.dart';

import '../../core/node_icons.dart';
import '../../core/palette.dart';
import '../../core/theme.dart';
import '../../data/library.dart';
import '../../state/inventory_host.dart';
import '../../state/inventory_store.dart';
import 'icon_picker_sheet.dart';

/// Envanterin amblemi: kullanıcının seçtiği renkte küçük bir kare, içinde
/// seçtiği simge. Başlıkta, sol menüde ve envanter listesinde aynı işaret
/// durur: "Ev" ile "Atölye" adını okumadan ayrılsın.
///
/// Seçim yapılmadıysa eski sade görünüm: açık olan kiremit, ötekiler soluk.
class InventoryEmblem extends StatelessWidget {
  const InventoryEmblem({super.key, required this.entry, this.size = 44, this.active = false});

  final InventoryEntry entry;
  final double size;

  /// Açık envanter (seçilmiş bir renk yoksa kiremit zeminle belirtilir).
  final bool active;

  /// Tanınmayan anahtar (ör. daha yeni bir sürümden kalan) varsayılan kutuya düşer.
  static IconData glyphOf(InventoryEntry entry) => NodeIcons.byKey(entry.glyph) ?? Icons.inventory_2_rounded;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final chosen = entry.color;
    final background = chosen != null
        ? cardTone(chosen, Theme.of(context).brightness)
        : (active ? tones.accent : tones.raised);
    final ink = chosen != null ? onColorOf(background) : (active ? tones.onAccent : tones.muted);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(glyphOf(entry), size: size * 0.55, color: ink),
    );
  }
}

/// Envanterin rengini ve amblemini seçtiren sayfa. Her dokunuş hemen
/// uygulanır (arkadaki liste ve başlık da değişir): "kaydet" yok.
Future<void> pickInventoryLook(BuildContext context, InventoryEntry entry) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => _LookSheet(id: entry.id),
    );

class _LookSheet extends StatelessWidget {
  const _LookSheet({required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final host = LibraryScope.maybeOf(context);
    final entry = host?.library.byId(id);
    if (host == null || entry == null) return const SizedBox.shrink();
    final s = InventoryScope.of(context).strings;
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final glyph = NodeIcons.isKnown(entry.glyph) ? entry.glyph : null;
    // Simge ızgarasında seçili olan, envanterin rengiyle boyanır.
    final tint = entry.color != null ? cardTone(entry.color!, theme.brightness) : tones.accent;

    Widget swatch({
      required Key key,
      required Color? color,
      required bool selected,
      required VoidCallback onTap,
      String? tooltip,
    }) {
      final dot = GestureDetector(
        key: key,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 40,
          height: 40,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? tones.ink : tones.line, width: selected ? 3 : 1),
          ),
          child: color == null
              ? (selected
                  ? Icon(Icons.check_rounded, size: 19, color: tones.ink)
                  : Icon(Icons.format_color_reset_rounded, size: 19, color: tones.muted))
              : (selected ? Icon(Icons.check_rounded, size: 19, color: tones.ink) : null),
        ),
      );
      return tooltip == null ? dot : Tooltip(message: tooltip, child: dot);
    }

    Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Text(
            s.upper(text),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 2),
                  child: Row(
                    children: [
                      InventoryEmblem(entry: entry, size: 48, active: id == host.library.activeId),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              host.nameOf(entry, s),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge,
                            ),
                            Text(s.inventoryLook, style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.done)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: Text(s.inventoryLookHint, style: theme.textTheme.bodySmall),
                ),
                label(s.lookColor),
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      swatch(
                        key: const ValueKey('look-none'),
                        color: null,
                        selected: entry.color == null,
                        tooltip: s.lookNoColor,
                        onTap: () => host.setColor(id, null),
                      ),
                      for (final c in kCardPalette) ...[
                        const SizedBox(width: 10),
                        swatch(
                          key: ValueKey('look-${c.toARGB32()}'),
                          color: cardTone(c.toARGB32(), theme.brightness),
                          selected: c.toARGB32() == entry.color,
                          onTap: () => host.setColor(id, c.toARGB32()),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Row(
                    children: [
                      Expanded(child: label(s.lookEmblem)),
                      IconChoiceTile(
                        icon: Icons.inventory_2_rounded,
                        color: tint,
                        selected: glyph == null,
                        label: s.defaultIcon,
                        onTap: () => host.setGlyph(id, null),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...iconGroupSlivers(
            context,
            selected: glyph,
            color: tint,
            onPick: (key) => host.setGlyph(id, key),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
