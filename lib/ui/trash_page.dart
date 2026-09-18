import 'package:flutter/material.dart';

import '../state/inventory_store.dart';
import '../core/theme.dart';
import 'widgets/paper.dart';
import 'widgets/ink_art.dart';
import 'shell.dart';

/// Silinen kartlar. Klasör silindiyse içindekiler de onunla birlikte
/// görünmez olur; geri alinca hepsi geri döner.
class TrashPage extends StatelessWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final items = store.trash;
    final purged = store.recentlyPurged;
    final theme = Theme.of(context);

    Future<void> emptyAll() async {
      final now = await _confirmDelete(
        context,
        title: s.emptyTrashQuestion,
        body: s.emptyTrashWarning,
        action: s.emptyTrash,
      );
      if (now != null) await store.emptyTrash(now: now);
    }

    // "Son silinenler"in tamamı beklemeden: yer açmak için (30 gün dolmadan).
    Future<void> clearPurged() async {
      final count = purged.fold<int>(0, (sum, p) => sum + 1 + p.inside);
      final ok = await _confirm(
        context,
        title: s.clearPurgedQuestion,
        body: s.clearPurgedWarning(count),
        action: s.deleteNow,
      );
      if (ok) await store.discardPurged();
    }

    return Scaffold(
      appBar: ShellHeader(
        eyebrow: items.isEmpty ? null : s.recordCount(items.length),
        title: s.trash,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        trailing: items.isEmpty
            ? null
            : TextButton(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: emptyAll,
                child: Text(s.emptyTrash),
              ),
      ),
      body: items.isEmpty && purged.isEmpty
          ? EmptyState(art: InkArtKind.trash, title: s.trashEmpty, body: s.trashEmptyHint)
          : ListView.separated(
              padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 8, 16, 24)),
              itemCount: items.length + (purged.isEmpty ? 0 : 1 + purged.length),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i >= items.length) {
                  // Kalıcı silinenler: 30 gün geri getirilebilir.
                  if (i == items.length) {
                    return Padding(
                      padding: EdgeInsets.fromLTRB(6, items.isEmpty ? 4 : 22, 0, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.recentlyPurged,
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(s.recentlyPurgedHint, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                            onPressed: clearPurged,
                            child: Text(s.clearPurged),
                          ),
                        ],
                      ),
                    );
                  }
                  final p = purged[i - items.length - 1];
                  final left = InventoryStore.keepPurged.inDays - DateTime.now().difference(p.at).inDays;
                  return RecordTile(
                    node: p.node,
                    title: store.nameOf(p.node),
                    subtitle: [
                      if (p.inside > 0) s.insideCount(p.inside),
                      s.daysLeft(left < 1 ? 1 : left),
                    ].join(' · '),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.restore_rounded),
                          tooltip: s.restoreInventory,
                          onPressed: () => store.restorePurged(p.node.id),
                        ),
                        // 30 gün dolmadan tamamen: fotoğrafları ve ekleriyle.
                        IconButton(
                          icon: const Icon(Icons.delete_forever_rounded),
                          tooltip: s.deleteNow,
                          color: theme.colorScheme.error,
                          onPressed: () async {
                            final ok = await _confirm(
                              context,
                              title: s.deleteNowQuestion(store.nameOf(p.node)),
                              body: s.deleteNowWarning,
                              action: s.deleteNow,
                            );
                            if (ok) await store.discardPurged(p.node.id);
                          },
                        ),
                      ],
                    ),
                  );
                }
                final node = items[i];
                final inside = node.isContainer ? store.descendantCount(node.id) : 0;
                return RecordTile(
                  node: node,
                  title: store.nameOf(node),
                  subtitle: inside > 0 ? s.insideCount(inside) : s.singleRecord,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore_rounded),
                        tooltip: s.undo,
                        onPressed: () => store.restore(node.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever_rounded),
                        tooltip: s.deleteForever,
                        color: theme.colorScheme.error,
                        onPressed: () async {
                          final now = await _confirmDelete(
                            context,
                            title: s.deleteForeverQuestion(store.nameOf(node)),
                            body: inside > 0 ? s.deleteForeverWarning(inside) : s.purgeRecoverable,
                            action: s.delete,
                          );
                          if (now != null) await store.deleteForever(node.id, now: now);
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Düz onay: vazgeçilirse ya da pencere dışına dokunulursa false.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final s = InventoryScope.read(context).strings;
  final theme = Theme.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Kalıcı silme onayı. Varsayılan olarak kayıt "Son silinenler"de 30 gün bekler (yanlışlıkla
/// silineni geri getirmek için); kutu işaretlenirse beklemeden, fotoğrafları ve ekleriyle tamamen
/// silinir. Vazgeçilirse null, yoksa "hemen mi".
Future<bool?> _confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(title: title, body: body, action: action),
    );

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.title, required this.body, required this.action});

  final String title;
  final String body;
  final String action;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  bool _now = false;

  @override
  Widget build(BuildContext context) {
    final s = InventoryScope.of(context).strings;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_now ? s.deleteNowWarning : widget.body),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _now,
            onChanged: (v) => setState(() => _now = v ?? false),
            title: Text(s.deleteNowOption),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
        FilledButton(
          style: _now
              ? FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  foregroundColor: theme.colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(_now),
          child: Text(_now ? s.deleteNow : widget.action),
        ),
      ],
    );
  }
}
