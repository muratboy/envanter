import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/date_notifier.dart';
import '../../state/inventory_host.dart';
import '../../state/inventory_store.dart';
import '../../sync/discovery.dart';
import '../../sync/sharing_service.dart';
import '../widgets/text_prompt.dart';
import 'sharing_scope.dart';

/// Ortak kullanımın kullanıcıya soran adımları; hem ortak kullanım
/// sayfası hem ayarlar aynılarını kullanır.
abstract final class SharingFlows {
  static Future<void> toggle(BuildContext context, bool on) async {
    final sharing = SharingScope.read(context);
    // Ağda adsız görünmesin: açarken ad yoksa sorulur.
    if (on && !await ensureNames(context, askInventory: sharing.config.isOwner)) return;
    await sharing.setEnabled(on);
    // Onay bekleyenler bildirimi için izin, ortak kullanım ilk açıldığında bir kez sorulur.
    if (on) unawaited(DateNotifier.instance.askOnce(sharing: true));
  }

  /// Değişiklikleri sormadan uygula; açılınca bekleyenler de hemen uygulanır.
  static Future<void> setAutoAccept(BuildContext context, bool on) async {
    final sharing = SharingScope.read(context);
    final store = InventoryScope.read(context);
    await sharing.setAutoAccept(on);
    if (on) await store.acceptAllChanges();
  }

  /// Adı yoksa sorar; açılmaktan vazgeçilirse false.
  static Future<bool> ensureNames(BuildContext context, {required bool askInventory}) async {
    final store = InventoryScope.read(context);
    final sharing = SharingScope.read(context);
    // Envanterin adı çoğu zaman zaten var (Envanterler'de verilen): ağda da o görünsün.
    final libraryName = LibraryScope.read(context)?.library.active.name.trim() ?? '';
    if (askInventory && sharing.config.inventoryName.trim().isEmpty && libraryName.isNotEmpty) {
      await sharing.rename(libraryName);
      if (!context.mounted) return false;
    }
    final hasName = store.settings.userName.trim().isNotEmpty;
    final hasInventory = sharing.config.inventoryName.trim().isNotEmpty;
    if (hasName && (!askInventory || hasInventory)) return true;

    final s = store.strings;
    final values = await showTextPrompt(
      context,
      title: s.sharingNeedsNameTitle,
      message: s.sharingNeedsNameHint,
      fields: [
        PromptField(
          label: s.yourName,
          initial: store.settings.userName,
          capitalization: TextCapitalization.words,
        ),
        if (askInventory)
          PromptField(
            label: s.inventoryNameLabel,
            initial: sharing.config.inventoryName,
            hint: s.inventoryNameHint,
          ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values == null) return false;
    final name = values.first.trim();
    final inventory = askInventory ? values.last.trim() : '';
    if (name.isEmpty) return false;
    await store.updateSettings(store.settings.copyWith(userName: name));
    if (askInventory && inventory.isNotEmpty) await sharing.rename(inventory);
    return true;
  }

  static Future<void> rename(BuildContext context) async {
    final sharing = SharingScope.read(context);
    final s = InventoryScope.read(context).strings;
    final values = await showTextPrompt(
      context,
      title: s.inventoryNameLabel,
      fields: [
        PromptField(label: s.inventoryNameLabel, initial: sharing.inventoryName, hint: s.inventoryNameHint),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    final name = values?.single.trim() ?? '';
    if (name.isEmpty || !context.mounted) return;
    // Envanterin tek bir adı var: ağda görünen de, Envanterler listesindeki de.
    final host = LibraryScope.read(context);
    if (host != null) {
      await host.rename(host.library.activeId, name);
    } else {
      await sharing.rename(name);
    }
  }

  static Future<void> join(BuildContext context, DiscoveredPeer peer) async {
    final sharing = SharingScope.read(context);
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final inventory = peer.info.inventoryName;
    final owner = peer.info.deviceName.isEmpty ? s.user : peer.info.deviceName;

    if (!await ensureNames(context, askInventory: false)) return;
    if (!context.mounted) return;

    final local = store.liveRecordCount;
    // Bu envanterde kayıt varsa önerilen: katılınan envanter ayrı bir envanter
    // olur, buradakiler karışmaz. İstenirse eskisi gibi birleştirilir.
    final host = LibraryScope.read(context);
    final separate = host != null && local > 0;
    final choice = await showDialog<_JoinChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.group_add_rounded),
        title: Text(s.joinQuestion(inventory)),
        content: Text([
          s.joinOwnerLine(owner),
          if (separate) s.joinSeparateHint(local) else if (local > 0) s.joinMergeWarning(local),
        ].join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel)),
          if (separate)
            TextButton(onPressed: () => Navigator.of(context).pop(_JoinChoice.merge), child: Text(s.joinIntoCurrent)),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(separate ? _JoinChoice.separate : _JoinChoice.merge),
            child: Text(separate ? s.joinAsNew : s.sendRequest),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == _JoinChoice.separate) {
      // Yeni envantere geçilir, arayüz baştan kurulur; bekleme penceresini ve
      // sonucu oradaki SharingHost gösterir.
      unawaited(host!.joinAsNew(peer, owner: owner));
      return;
    }

    // Onay beklerken kapatılamayan küçük pencere.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              const SizedBox(width: 18),
              Expanded(child: Text(s.waitingForApproval(owner))),
            ],
          ),
        ),
      ),
    );
    final outcome = await sharing.requestJoin(peer);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        JoinOutcome.accepted => s.joinedMessage(inventory),
        JoinOutcome.rejected => s.joinRejected,
        JoinOutcome.unreachable => s.joinUnreachable,
        JoinOutcome.timeout => s.joinTimeout,
        JoinOutcome.incompatible => s.joinIncompatible,
      }),
    ));
  }

  /// Ortaklıktan ayrılır. Yönetici ayrılırken envanteri kimin yöneteceğini
  /// seçer (varis önde; başkası da seçilebilir), diğerlerine haber gider.
  /// [deleting]: envanter bu cihazdan siliniyor; onayı çağıran aldı, burada
  /// yalnızca yönetici seçimi sorulur. Ayrıldıysa true.
  static Future<bool> leave(BuildContext context, {bool deleting = false}) async {
    final sharing = SharingScope.read(context);
    final store = InventoryScope.read(context);
    final s = store.strings;
    final c = sharing.config;
    String? newOwner;
    final others = [for (final m in c.members) if (m.deviceId != c.deviceId) m];
    if (c.isOwner && others.isNotEmpty) {
      // Varis en üstte: çoğu zaman o seçilir.
      final heir = c.heir;
      others.sort((a, b) => (b.deviceId == heir ? 1 : 0) - (a.deviceId == heir ? 1 : 0));
      newOwner = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(s.chooseSuccessorTitle),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(s.chooseSuccessorBody),
            ),
            for (final m in others)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(m.deviceId),
                child: Row(
                  children: [
                    NameAvatar(name: m.name.isEmpty ? s.user : m.name),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text([
                        m.name.isEmpty ? s.user : m.name,
                        if (m.deviceId == heir) s.heirSuffix,
                      ].join(' ')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
      if (newOwner == null || !context.mounted) return false;
    }
    if (!deleting) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(s.leaveSharingQuestion),
          content: Text(s.leaveSharingBody),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.leave)),
          ],
        ),
      );
      if (ok != true) return false;
    }
    await sharing.leave(newOwner: newOwner, deleted: deleting);
    // Artık o envanterin değişiklikleri beklenmiyor.
    await store.discardPendingChanges();
    return true;
  }

  /// Yönetici yöneticiliği bir üyeye devreder (onayla); kendisi varis olur.
  static Future<void> transferOwnership(BuildContext context, String deviceId, String name) async {
    final sharing = SharingScope.read(context);
    final s = InventoryScope.read(context).strings;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.transferQuestion(name)),
        content: Text(s.transferBody(name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.transfer)),
        ],
      ),
    );
    if (ok != true) return;
    if (await sharing.transferOwnership(deviceId)) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(s.newOwnerIs(name))));
    }
  }

  /// Yönetici varis seçer ya da kaldırır.
  static Future<void> setHeir(BuildContext context, String? deviceId, String name) async {
    final sharing = SharingScope.read(context);
    final s = InventoryScope.read(context).strings;
    final messenger = ScaffoldMessenger.of(context);
    if (await sharing.setHeir(deviceId)) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(deviceId == null ? s.heirCleared : s.heirSet(name))));
    }
  }

  /// Ana kullanıcı bir üyeyi ortak kullanımdan çıkarır (onayla).
  static Future<void> removeMember(BuildContext context, String deviceId, String name) async {
    final sharing = SharingScope.read(context);
    final s = InventoryScope.read(context).strings;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.removeMemberQuestion(name)),
        content: Text(s.removeMemberBody(name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.remove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (await sharing.removeMember(deviceId)) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(s.memberRemoved(name))));
    }
  }

  /// "Son eşitleme: 14:32" gibi.
  static String lastSyncLabel(BuildContext context, DateTime? at) {
    final s = InventoryScope.of(context).strings;
    if (at == null) return s.neverSynced;
    final t = TimeOfDay.fromDateTime(at).format(context);
    final today = DateUtils.isSameDay(at, DateTime.now());
    final label = today ? t : '${MaterialLocalizations.of(context).formatShortDate(at)} $t';
    return s.lastSynced(label);
  }

  /// "az önce", "5 dk önce", "3 sa önce" ya da tarih.
  static String ago(BuildContext context, DateTime at) {
    final s = InventoryScope.of(context).strings;
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return s.justNow;
    if (diff.inMinutes < 60) return s.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return s.hoursAgo(diff.inHours);
    if (diff.inDays < 7) return s.daysAgo(diff.inDays);
    return MaterialLocalizations.of(context).formatShortDate(at);
  }
}

/// Bir adın baş harfiyle, adına göre hep aynı renkte yuvarlak.
class NameAvatar extends StatelessWidget {
  const NameAvatar({super.key, required this.name, this.radius = 20, this.online});

  final String name;
  final double radius;

  /// null: durum gösterilmez.
  final bool? online;

  static const _colors = [
    Color(0xFF3F6C8C),
    Color(0xFF2E8B72),
    Color(0xFFC67A2E),
    Color(0xFFB03A46),
    Color(0xFF7D4AA0),
    Color(0xFF2F8FA3),
    Color(0xFF8A9A2B),
    Color(0xFFA63C6E),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    // Kendi özetimiz: adın rengi her açılışta ve her cihazda aynı kalsın.
    final hash = trimmed.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff);
    final color = _colors[hash % _colors.length];
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: radius * 0.85),
      ),
    );
    if (online == null) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: radius * 0.62,
            height: radius * 0.62,
            decoration: BoxDecoration(
              color: online! ? const Color(0xFF2FB36B) : Theme.of(context).colorScheme.outline,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Katılırken: ayrı bir envanter mi, bu envanterle birleştirme mi.
enum _JoinChoice { separate, merge }
