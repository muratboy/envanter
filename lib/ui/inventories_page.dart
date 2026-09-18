import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../data/library.dart';
import '../state/inventory_host.dart';
import '../state/inventory_store.dart';
import 'sharing/sharing_flows.dart';
import 'sharing/sharing_scope.dart';
import 'shell.dart';
import 'widgets/inventory_emblem.dart';
import 'widgets/node_card.dart';
import 'widgets/text_prompt.dart';

/// Bu cihazdaki envanterler (Obsidian'daki kasalar gibi): biri açık, ötekiler
/// dokunulmadan durur. Dokununca o envantere geçilir; yeni boş envanter
/// açılabilir, ad değiştirilebilir, silinebilir. Silinen 30 gün Silinenler'de
/// durur (bir dokunuşla giden envanter geri gelmiyordu).
class InventoriesPage extends StatelessWidget {
  const InventoriesPage({super.key});

  /// Sıfırdan boş bir envanter: adı sorulur, açılır.
  static Future<void> create(BuildContext context) async {
    final host = LibraryScope.read(context);
    final s = InventoryScope.read(context).strings;
    if (host == null) return;
    final values = await showTextPrompt(
      context,
      title: s.newInventory,
      message: s.newInventoryHint,
      fields: [PromptField(label: s.inventoryNameLabel, hint: s.inventoryNameHint)],
      cancelLabel: s.cancel,
      confirmLabel: s.create,
    );
    final name = values?.single.trim() ?? '';
    if (name.isEmpty) return;
    await host.create(name);
  }

  /// Envanterin adını değiştirir (açık olanınki de, kapalı olanınki de). Açık
  /// envanteri paylaşan sahipse ağda görünen adı da değişir.
  static Future<void> rename(BuildContext context, InventoryEntry entry) async {
    final host = LibraryScope.read(context);
    final s = InventoryScope.read(context).strings;
    if (host == null) return;
    final values = await showTextPrompt(
      context,
      title: s.renameInventory,
      fields: [
        PromptField(label: s.inventoryNameLabel, initial: host.nameOf(entry, s), hint: s.inventoryNameHint),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    final name = values?.single.trim() ?? '';
    if (name.isEmpty) return;
    await host.rename(entry.id, name);
  }

  /// Silinenler'e taşır. Paylaşılan envanterde önce diğerlerine haber gider
  /// (yöneticiyse yönetimi kime bırakacağı sorulur); kapalıysa bunun için önce
  /// açılır, gerisini yeni arayüz yürütür (`SharingHost`, [InventoryHost.takePendingDelete]).
  static Future<void> delete(BuildContext context, InventoryEntry entry) async {
    final host = LibraryScope.read(context);
    final store = InventoryScope.read(context);
    final s = store.strings;
    if (host == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final active = entry.id == host.library.activeId;
    final shared = active ? SharingScope.read(context).config.isShared : entry.shared;
    final name = host.nameOf(entry, s);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.deleteInventoryQuestion(name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.deleteInventoryBody(active ? store.totalRecordCount : entry.count)),
            if (shared) ...[
              const SizedBox(height: 12),
              Text(active ? s.deleteSharedNote : s.deleteSharedClosedNote),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (shared && !active) {
      await host.openToDelete(entry.id);
      return;
    }
    if (shared && !await SharingFlows.leave(context, deleting: true)) return;
    await host.delete(entry.id);
    // Açık olan silindiyse arayüz baştan kuruldu; bu sayfa artık yok.
    if (active) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.inventoryDeleted(name)),
      action: SnackBarAction(label: s.restoreInventory, onPressed: () => host.restoreDeleted(entry.id)),
    ));
  }

  Future<void> _purge(BuildContext context, InventoryHost host, InventoryEntry entry) async {
    final s = InventoryScope.read(context).strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.purgeInventoryQuestion(host.nameOf(entry, s))),
        content: Text(s.purgeInventoryBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.purgeInventory),
          ),
        ],
      ),
    );
    if (ok == true) await host.purgeDeleted(entry.id);
  }

  /// Kaydın yedek satırı: son yedek ya da (içi doluysa) yedeği yok.
  static String? _backupLine(AppStrings s, DateTime? at, bool empty) => at != null
      ? s.lastBackupOn(s.formatDate(at))
      : empty
          ? null
          : s.noBackup;

  @override
  Widget build(BuildContext context) {
    final host = LibraryScope.maybeOf(context);
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    if (host == null) return const SizedBox.shrink();
    final library = host.library;
    final unbacked = host.unbackedEntries;
    final trashed = [...library.trashed]
      ..sort((a, b) => (b.deletedAt ?? b.createdAt).compareTo(a.deletedAt ?? a.createdAt));
    // Açık olan en üstte, sonra en son açılanlar.
    final entries = [...library.entries]
      ..sort((a, b) {
        if (a.id == library.activeId) return -1;
        if (b.id == library.activeId) return 1;
        final at = a.openedAt ?? a.createdAt;
        final bt = b.openedAt ?? b.createdAt;
        return bt.compareTo(at);
      });

    return Scaffold(
      appBar: ShellHeader(
        title: s.inventories,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: readableInsets(context, const EdgeInsets.fromLTRB(16, 4, 16, 32)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
            child: Text(s.inventoriesHint, style: theme.textTheme.bodySmall),
          ),
          // Otomatik yedek açık ama bazı envanterler o zamandan beri açılmadı.
          if (unbacked.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              decoration: BoxDecoration(
                color: tones.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tones.danger),
              ),
              child: Row(
                children: [
                  Icon(Icons.backup_rounded, color: tones.danger),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.unbackedInventories(unbacked.length))),
                  TextButton(onPressed: host.backupAll, child: Text(s.backupNow)),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          for (final entry in entries)
            if (entry.id == library.activeId) ...[
              _InventoryCard(
                entry: entry,
                name: host.nameOf(entry, s),
                detail: [s.recordCount(store.totalRecordCount), s.openNow].join(' · '),
                pending: store.pendingCount,
                backup: _backupLine(s, store.settings.lastBackupAt, store.totalRecordCount == 0),
                backupMissing: store.settings.lastBackupAt == null,
                active: true,
                // Açık olana dokunmak adını değiştirir; ötekine dokunmak ona geçer.
                onTap: () => rename(context, entry),
                onRename: () => rename(context, entry),
                onLook: () => pickInventoryLook(context, entry),
                onDelete: () => delete(context, entry),
              ),
              const SizedBox(height: 10),
            ] else ...[
              _InventoryCard(
                entry: entry,
                name: host.nameOf(entry, s),
                detail: [
                  s.recordCount(entry.count),
                  if (entry.openedAt case final at?) s.lastOpened(s.formatDate(at)),
                ].join(' · '),
                // Kapanırken ya da arka planda eşitlenince sayılan: açmadan görünsün.
                pending: entry.pending,
                // Bu bilgiden önce kapanmış envanterin yedeği bilinmez: satır yok.
                backup: entry.backupKnown ? _backupLine(s, entry.backedUpAt, entry.count == 0) : null,
                backupMissing: entry.backedUpAt == null,
                active: false,
                onTap: () => host.open(entry.id),
                onRename: () => rename(context, entry),
                onLook: () => pickInventoryLook(context, entry),
                onDelete: () => delete(context, entry),
              ),
              const SizedBox(height: 10),
            ],
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: () => create(context),
            icon: const Icon(Icons.add_rounded),
            label: Text(s.newInventory),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
          if (trashed.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 30, 6, 4),
              child: Text(
                s.deletedInventories,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Text(s.deletedInventoriesHint, style: theme.textTheme.bodySmall),
            ),
            for (final entry in trashed) ...[
              _DeletedCard(
                name: host.nameOf(entry, s),
                detail: [
                  s.recordCount(entry.count),
                  s.daysLeft(math.max(1, InventoryLibrary.keepDeleted.inDays -
                      DateTime.now().difference(entry.deletedAt ?? DateTime.now()).inDays)),
                ].join(' · '),
                onRestore: () => host.restoreDeleted(entry.id),
                onPurge: () => _purge(context, host, entry),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.entry,
    required this.name,
    required this.detail,
    required this.pending,
    required this.backup,
    required this.backupMissing,
    required this.active,
    required this.onTap,
    required this.onRename,
    required this.onLook,
    required this.onDelete,
  });

  final InventoryEntry entry;
  final String name;
  final String detail;

  /// Onay bekleyen değişiklik sayısı (ortak kullanımda başkalarından gelenler).
  final int pending;

  /// Son yedek satırı; içi boşsa yok.
  final String? backup;
  final bool backupMissing;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback onRename;

  /// Renk ve amblem seçimi.
  final VoidCallback onLook;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final s = InventoryScope.of(context).strings;
    final emblem = InventoryEmblem(entry: entry, active: active);
    return Material(
      color: active ? tones.raised : tones.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? tones.accent : tones.line, width: active ? 1.6 : 1),
          ),
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(
            children: [
              // Açık olanın amblemine dokunmak seçimi açar. Kapalı olanda dokunuş
              // karta gider: geçmek isteyen kişi doğal olarak simgeye basıyor.
              if (active)
                Tooltip(message: s.inventoryLook, child: GestureDetector(onTap: onLook, child: emblem))
              else
                emblem,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: kDisplayFont, fontSize: 19, fontWeight: FontWeight.w600, color: tones.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(detail, style: theme.textTheme.bodySmall),
                    // Onay bekleyen değişiklik: envanteri açmadan görünsün.
                    if (pending > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, bottom: 1),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const PendingDot(size: 9),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                s.pendingInInventory(pending),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: tones.accent, fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (backup case final line?)
                      Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(color: backupMissing ? tones.danger : null),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<int>(
                tooltip: s.options,
                onSelected: (choice) => switch (choice) {
                  0 => onRename(),
                  1 => onLook(),
                  _ => onDelete(),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 0, child: Text(s.renameInventory)),
                  PopupMenuItem(value: 1, child: Text(s.inventoryLook)),
                  PopupMenuItem(
                    value: 2,
                    child: Text(s.delete, style: TextStyle(color: theme.colorScheme.error)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Silinenler'deki bir envanter: geri getirilir ya da kalıcı silinir.
class _DeletedCard extends StatelessWidget {
  const _DeletedCard({required this.name, required this.detail, required this.onRestore, required this.onPurge});

  final String name;
  final String detail;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final s = InventoryScope.of(context).strings;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tones.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: Row(
        children: [
          Icon(Icons.delete_outline_rounded, color: tones.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: kDisplayFont, fontSize: 17, fontWeight: FontWeight.w600, color: tones.muted),
                ),
                Text(detail, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(onPressed: onRestore, child: Text(s.restoreInventory)),
          // Değeri null olan öğe seçilince Flutter onSelected'ı çağırmıyor (iptal sayıyor).
          PopupMenuButton<bool>(
            tooltip: s.options,
            onSelected: (_) => onPurge(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: true,
                child: Text(s.purgeInventory, style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
