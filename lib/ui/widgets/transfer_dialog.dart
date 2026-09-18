import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/node.dart';
import '../../state/inventory_host.dart';
import '../../state/inventory_store.dart';
import 'inventory_emblem.dart';

/// Envanterler arası kayıt taşıma / kopyalama alt penceresi.
Future<void> showTransferDialog(BuildContext context, List<Node> nodes) async {
  if (nodes.isEmpty) return;
  final host = LibraryScope.read(context);
  final store = InventoryScope.read(context);
  final s = store.strings;
  final messenger = ScaffoldMessenger.of(context);

  if (host == null || host.library.entries.length <= 1) {
    messenger.showSnackBar(SnackBar(content: Text(s.selectTargetInventory)));
    return;
  }

  final otherEntries = [
    for (final e in host.library.entries)
      if (e.id != host.library.activeId) e,
  ];

  if (otherEntries.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s.cannotTransferToSame)));
    return;
  }

  var selectedId = otherEntries.first.id;
  var isCopy = false;

  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final tones = Tones.of(sheetContext);
      final theme = Theme.of(sheetContext);
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s.transferOrCopyTitle,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    nodes.length == 1
                        ? store.nameOf(nodes.single)
                        : s.selectedCount(nodes.length),
                    style: theme.textTheme.bodyMedium?.copyWith(color: tones.muted),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    s.selectTargetInventory,
                    style: TextStyle(color: tones.muted, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final entry in otherEntries) ...[
                    RadioListTile<String>(
                      value: entry.id,
                      // ignore: deprecated_member_use
                      groupValue: selectedId,
                      contentPadding: EdgeInsets.zero,
                      secondary: InventoryEmblem(
                        entry: entry,
                        size: 36,
                      ),
                      title: Text(host.nameOf(entry, s), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(s.recordCount(entry.count)),
                      // ignore: deprecated_member_use
                      onChanged: (val) {
                        if (val != null) setSheetState(() => selectedId = val);
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text(s.transferAction),
                        icon: const Icon(Icons.drive_file_move_outlined),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text(s.copyAction),
                        icon: const Icon(Icons.copy_rounded),
                      ),
                    ],
                    selected: {isCopy},
                    onSelectionChanged: (val) => setSheetState(() => isCopy = val.first),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: Text(isCopy ? s.copyAction : s.transferAction),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  if (confirmed != true || !context.mounted) return;

  final targetEntry = host.library.byId(selectedId);
  final targetName = targetEntry != null ? host.nameOf(targetEntry, s) : selectedId;

  final count = await host.transferNodes(
    nodes: nodes,
    targetInventoryId: selectedId,
    isCopy: isCopy,
  );

  if (count > 0 && context.mounted) {
    final text = nodes.length == 1
        ? (isCopy ? s.copiedTo(store.nameOf(nodes.single), targetName) : s.transferredTo(store.nameOf(nodes.single), targetName))
        : (isCopy ? s.copiedMany(count, targetName) : s.transferredMany(count, targetName));
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}
