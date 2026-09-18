import 'package:flutter/material.dart';

import '../../core/node_icons.dart';
import '../../core/palette.dart';
import '../../data/node.dart';
import '../../state/inventory_store.dart';
import 'node_card.dart';

/// Kartın simgesini seçtiren sayfa. Seçilen anahtar döner; "varsayılan"
/// için boş metin, vazgeçilirse null.
Future<String?> pickNodeIcon(
  BuildContext context, {
  required NodeKind kind,
  required String? current,
  required Color color,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (context) => _IconPicker(kind: kind, current: current, color: color),
  );
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({required this.kind, required this.current, required this.color});

  final NodeKind kind;
  final String? current;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final selected = NodeIcons.isKnown(current) ? current : null;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(s.chooseIcon, style: theme.textTheme.titleLarge)),
                      IconChoiceTile(
                        icon: glyphFor(kind),
                        color: color,
                        selected: selected == null,
                        label: s.defaultIcon,
                        onTap: () => Navigator.of(context).pop(''),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...iconGroupSlivers(
            context,
            selected: selected,
            color: color,
            onPick: (key) => Navigator.of(context).pop(key),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

/// Simge grupları, başlıklarıyla: simge seçen her sayfa aynı ızgarayı kurar
/// (kartın simgesi, envanterin amblemi).
List<Widget> iconGroupSlivers(
  BuildContext context, {
  required String? selected,
  required Color color,
  required ValueChanged<String> onPick,
}) {
  final s = InventoryScope.of(context).strings;
  final theme = Theme.of(context);
  return [
    for (final group in NodeIcons.groups) ...[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            s.upper(group.label(s.locale)),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid.extent(
          maxCrossAxisExtent: 64,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            for (final e in group.icons.entries)
              IconChoiceTile(
                icon: e.value,
                color: color,
                selected: e.key == selected,
                onTap: () => onPick(e.key),
              ),
          ],
        ),
      ),
    ],
  ];
}

class IconChoiceTile extends StatelessWidget {
  const IconChoiceTile({
    super.key,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    this.label,
  });

  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = Material(
      color: selected ? color : scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected ? BorderSide(color: scheme.onSurface, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, size: 26, color: selected ? onColorOf(color) : scheme.onSurfaceVariant),
        ),
      ),
    );
    if (label == null) return tile;
    // Yazısına dokunmak da seçer (yalnızca kareye basmak gerekiyordu).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label!, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(width: 10),
          tile,
        ],
      ),
    );
  }
}
