import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/node.dart';
import '../../state/inventory_store.dart';
import '../../sync/review.dart';
import 'sharing_flows.dart';
import 'sharing_scope.dart';
import '../widgets/paper.dart';
import '../widgets/ink_art.dart';
import '../shell.dart';

/// Ortak kullananların yaptığı, onay bekleyen değişiklikler. Tek tek ya da
/// hepsi birden kabul edilir; reddedilince bizim sürüm kalır.
class ChangesPage extends StatelessWidget {
  const ChangesPage({super.key});

  Future<void> _rejectAll(BuildContext context) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.rejectAllQuestion),
        content: Text(s.rejectBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.rejectAll)),
        ],
      ),
    );
    if (ok == true) await store.rejectAllChanges();
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final groups = store.pendingGroups;

    return Scaffold(
      appBar: ShellHeader(
        eyebrow: groups.isEmpty ? null : s.pendingChanges(groups.length),
        title: s.changes,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (groups.isNotEmpty)
            PopupMenuButton<void>(
              tooltip: s.moreActions,
              icon: const Icon(Icons.more_vert_rounded),
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: () => _rejectAll(context),
                  child: Text(s.rejectAll),
                ),
              ],
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: groups.isEmpty
            ? const _AllCaughtUp()
            : ListView(
                key: const ValueKey('list'),
                padding: EdgeInsets.fromLTRB(0, 4, 0, 24 + bottomInset(context)),
                children: [
                  ReadableWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: theme.colorScheme.outline),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s.changesHint, style: theme.textTheme.bodySmall)),
                        ],
                      ),
                    ),
                  ),
                  for (final g in groups)
                    ReadableWidth(
                      key: ValueKey(g.id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: _ChangeCard(group: g),
                      ),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: groups.length < 2
          ? null
          : SafeArea(
              child: ReadableWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await store.acceptAllChanges();
                      messenger.showSnackBar(SnackBar(content: Text(s.changesAccepted)));
                    },
                    icon: const Icon(Icons.done_all_rounded),
                    label: Text('${s.acceptAll} (${groups.length})'),
                  ),
                ),
              ),
            ),
    );
  }
}

class _AllCaughtUp extends StatelessWidget {
  const _AllCaughtUp();

  @override
  Widget build(BuildContext context) {
    final s = InventoryScope.of(context).strings;
    return EmptyState(
      key: const ValueKey('empty'),
      art: InkArtKind.done,
      title: s.noPendingChanges,
      body: s.noPendingChangesBody,
    );
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({required this.group});

  final ChangeGroup group;

  IconData _icon(ChangeKind kind) => switch (kind) {
        ChangeKind.added => Icons.add_circle_rounded,
        ChangeKind.edited => Icons.edit_rounded,
        ChangeKind.moved => Icons.drive_file_move_rounded,
        ChangeKind.reordered => Icons.swap_vert_rounded,
        ChangeKind.trashed => Icons.delete_rounded,
        ChangeKind.restored => Icons.restore_from_trash_rounded,
        ChangeKind.deleted => Icons.delete_forever_rounded,
        ChangeKind.lost => Icons.travel_explore_rounded,
        ChangeKind.found => Icons.where_to_vote_rounded,
      };

  Color _tint(Tones t, ChangeKind kind) => switch (kind) {
        ChangeKind.added || ChangeKind.restored || ChangeKind.found => t.success,
        ChangeKind.lost => t.lost,
        ChangeKind.trashed || ChangeKind.deleted => t.danger,
        _ => t.accent,
      };

  String _headline(AppStrings s, ChangeKind kind, String who) => switch (kind) {
        ChangeKind.added => s.changeAdded(who),
        ChangeKind.edited => s.changeEdited(who),
        ChangeKind.moved => s.changeMoved(who),
        ChangeKind.reordered => s.changeReordered(who),
        ChangeKind.trashed => s.changeTrashed(who),
        ChangeKind.restored => s.changeRestored(who),
        ChangeKind.deleted => s.changeDeleted(who),
        ChangeKind.lost => s.changeLost(who),
        ChangeKind.found => s.changeFound(who),
      };

  /// Neyin değiştiği, kısaca.
  String? _detail(InventoryStore store, AppStrings s) {
    final sum = group.summary;
    final change = group.lead;
    final local = store.byId(change.nodeId);
    final inc = candidateOf(change, local);
    switch (sum.kind) {
      case ChangeKind.moved:
        if (local == null || inc == null) return null;
        final from = store.pathLabelForParent(local.parentId, inDrawer: local.inDrawer);
        final to = _placeOf(store, inc.parentId, inc.inDrawer);
        final rename = sum.renamed ? '\n${s.renamedFrom(sum.oldName!.isEmpty ? s.unnamed : sum.oldName!)}' : '';
        return '$from  →  $to$rename';
      case ChangeKind.edited:
        final fields = [
          if (sum.imageChanged) s.fieldPhoto,
          if (sum.colorChanged) s.fieldColor,
          if (sum.noteChanged) s.fieldNote,
          if (sum.kindChanged) s.fieldKind,
          if (sum.locationChanged) s.fieldLocation,
          if (sum.iconChanged) s.fieldIcon,
          if (sum.managersChanged) s.fieldManagers,
          if (sum.quantityChanged && inc?.quantity != null)
            '${s.fieldQuantity} ${inc!.quantity}${inc.unit != null ? " ${inc.unit}" : ""}'
          else if (sum.quantityChanged) s.fieldQuantity,
          if (sum.minQuantityChanged) s.fieldMinQuantity,
          if (sum.wantedChanged) s.fieldShopping,
          if (sum.fullChanged) s.fieldFull,
          if (sum.datesChanged) s.fieldDates,
          if (sum.attachmentsChanged) s.fieldAttachments,
          if (sum.barcodeChanged) s.fieldBarcode,
          if (sum.borrowChanged && inc?.isBorrowed == true)
            s.fieldBorrowed(inc!.borrowedTo!)
          else if (sum.borrowChanged)
            s.fieldReturned,
          if (sum.priceChanged && inc?.priceMoney != null)
            '${s.fieldPrice} ${s.money(inc!.priceMoney!)}'
          else if (sum.priceChanged)
            s.fieldPrice,
          if (sum.serialChanged) s.fieldSerial,
          // "Bakım yapıldı" günüyle; döngü değiştiyse yalnızca "bakım".
          if (sum.serviceChanged && inc?.servicedAt != null && inc!.servicedAt != local?.servicedAt)
            s.fieldServiced(s.formatDate(inc.servicedAt!))
          else if (sum.serviceChanged)
            s.fieldService,
        ];
        return [
          if (sum.renamed) s.renamedFrom(sum.oldName!.isEmpty ? s.unnamed : sum.oldName!),
          if (fields.isNotEmpty) s.changedFields(fields),
        ].join(' · ');
      case ChangeKind.added:
        if (inc == null) return null;
        final place = _placeOf(store, inc.parentId, inc.inDrawer);
        return group.extra > 0 ? '$place · ${s.andInside(group.extra)}' : place;
      case ChangeKind.deleted:
        final place = local == null ? null : store.pathLabel(local.id);
        if (group.extra > 0) return [?place, s.andInside(group.extra)].join(' · ');
        return place;
      case ChangeKind.reordered:
        final n = inc ?? local;
        if (n == null) return null;
        return s.reorderedIn(_placeOf(store, n.parentId, n.inDrawer));
      case ChangeKind.trashed:
      case ChangeKind.restored:
        return local == null ? null : store.pathLabel(local.id);
      case ChangeKind.lost:
        return local == null ? null : s.lastSeenIn(store.pathLabel(local.id));
      case ChangeKind.found:
        return inc == null ? null : _placeOf(store, inc.parentId, inc.inDrawer);
    }
  }

  /// Hedef henüz bizde olmayan (beklemedeki) bir klasör olabilir.
  String _placeOf(InventoryStore store, String? parentId, bool inDrawer) {
    if (parentId != null && store.byId(parentId) == null) {
      final pendingParent = store.pendingFor(parentId)?.incoming;
      if (pendingParent != null) {
        final name = store.nameOf(pendingParent);
        return '${store.pathLabelForParent(pendingParent.parentId, inDrawer: pendingParent.inDrawer)} / $name';
      }
    }
    return store.pathLabelForParent(parentId, inDrawer: inDrawer);
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final sharing = SharingScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final sum = group.summary;
    final lead = group.lead;
    final node = candidateOf(lead, store.byId(lead.nodeId)) ?? store.byId(lead.nodeId);
    final name = node == null ? s.unnamed : store.nameOf(node);
    final who = sharing.memberName(lead.author) ?? s.someone;
    final detail = sum.kind == ChangeKind.reordered ? null : _detail(store, s);
    final title = sum.kind == ChangeKind.reordered ? _detail(store, s) ?? name : name;
    final tones = Tones.of(context);
    final tint = _tint(tones, sum.kind);

    return Material(
      color: tones.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tones.line),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumb(node: node, badge: _icon(sum.kind), tint: tint),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          decoration: sum.kind == ChangeKind.deleted ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: _headline(s, sum.kind, who),
                            style: TextStyle(color: tint, fontWeight: FontWeight.w800),
                          ),
                          TextSpan(text: '  ·  ${SharingFlows.ago(context, group.changedAt)}'),
                        ]),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (detail != null && detail.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          detail,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await store.rejectChanges(group.nodeIds.toList());
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(SnackBar(content: Text(s.changesRejected)));
                  },
                  child: Text(s.reject),
                ),
                const SizedBox(width: 6),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await store.acceptChanges(group.nodeIds.toList());
                    messenger.hideCurrentSnackBar();
                    messenger.showSnackBar(SnackBar(content: Text(s.changesAccepted)));
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text(s.accept),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Kaydın küçük hali: fotoğrafı ya da rengi, köşesinde değişikliğin türü.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.node, required this.badge, required this.tint});

  final Node? node;
  final IconData badge;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final mark = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tint,
        shape: BoxShape.circle,
        border: Border.all(color: tones.surface, width: 2),
      ),
      child: Icon(badge, size: 13, color: tones.surface),
    );
    final n = node;
    if (n == null) {
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(color: tones.raised, borderRadius: BorderRadius.circular(16)),
      );
    }
    return RecordThumb(node: n, size: 54, badge: mark);
  }
}

/// Üst çubuktaki zil: bekleyen değişiklik sayısı. Yeni değişiklik gelince
/// kısaca sallanır.
class ChangesBell extends StatefulWidget {
  const ChangesBell({super.key});

  @override
  State<ChangesBell> createState() => _ChangesBellState();
}

class _ChangesBellState extends State<ChangesBell> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  int _last = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = InventoryScope.of(context).pendingCount;
    if (_last >= 0 && n > _last) _shake.forward(from: 0);
    _last = n;
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final n = store.pendingCount;

    return IconButton(
      tooltip: store.strings.pendingChanges(n),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChangesPage()),
      ),
      icon: AnimatedBuilder(
        animation: _shake,
        builder: (context, child) {
          final t = _shake.value;
          // Sönümlenen salınım.
          final angle = t == 0 ? 0.0 : 0.35 * (1 - t) * _wave(t * 6);
          return Transform.rotate(angle: angle, alignment: Alignment.topCenter, child: child);
        },
        child: Badge(
          isLabelVisible: n > 0,
          label: Text('$n'),
          child: Icon(n > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
        ),
      ),
    );
  }

  static double _wave(double x) {
    final f = x - x.floorToDouble();
    return f < 0.5 ? (f * 4 - 1) : (3 - f * 4);
  }
}
