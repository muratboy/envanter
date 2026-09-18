import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_paths.dart';
import '../../services/image_service.dart';
import '../../state/inventory_host.dart';
import '../../state/inventory_store.dart';
import '../backup_flows.dart';
import '../inventories_page.dart';
import '../audit_page.dart';
import '../dates_page.dart';
import '../lending_page.dart';
import '../shopping_page.dart';
import '../settings_page.dart';
import '../sharing/changes_page.dart';
import '../sharing/sharing_page.dart';
import '../sharing/sharing_scope.dart';
import '../shell.dart';
import 'inventory_emblem.dart';
import 'text_prompt.dart';
import '../trash_page.dart';
import '../value_page.dart';
import '../../core/theme.dart';
import '../../core/palette.dart';

/// Sol üst simgeden açılan çekmece: kullanıcı, ayarlar ve çöp kutusu.
class LeftDrawer extends StatelessWidget {
  const LeftDrawer({super.key});

  Future<void> _editProfile(BuildContext context) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final values = await showTextPrompt(
      context,
      title: s.userNameTitle,
      fields: [
        PromptField(
          label: s.yourName,
          initial: store.settings.userName,
          capitalization: TextCapitalization.words,
        ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values == null) return;
    await store.updateSettings(store.settings.copyWith(userName: values.single.trim()));
  }

  Future<void> _pickAvatar(BuildContext context) async {
    final store = InventoryScope.read(context);
    final path = await ImageService.pick(ImageSource.gallery, personal: true);
    if (path == null) return;
    ImageService.discardPersonal(store.settings.userAvatarPath);
    await store.updateSettings(store.settings.copyWith(userAvatarPath: path));
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final theme = Theme.of(context);
    final settings = store.settings;
    final avatar = AppPaths.rootImageFile(settings.userAvatarPath);
    final trashCount = store.trash.length;
    final drawerCount = store.childrenOf(Roots.drawer).length;
    final sharing = SharingScope.of(context);
    final pending = store.pendingCount;
    final lostCount = store.childrenOf(Roots.lost).length;
    final favoriteCount = store.favorites.length;
    // Tarihi geçen ya da yaklaşanlar ve bakımı gelenler: hepsi "Tarihi yaklaşanlar"da.
    final expiring = store.expiryAlerts.length + store.serviceDue.length;
    final expired = store.expiredItems.length;
    final toBuy = store.shoppingCount;
    final borrowedCount = store.borrowedItems.length;
    final hasOverdueBorrow = store.hasOverdueBorrow;

    void push(Widget page) {
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.push(MaterialPageRoute(builder: (_) => page));
    }

    final tones = Tones.of(context);
    // Birden çok envanter olabilir: menünün başlığı açık olanın adı, yanında geçiş.
    final host = LibraryScope.maybeOf(context);
    final inventoryName = host == null ? s.appTitle : host.nameOf(host.library.active, s);

    // Kapalı bir envanterde onay bekleyen değişiklik var (arka planda eşitlenince gelir).
    final pendingElsewhere =
        host != null && host.library.entries.any((e) => e.id != host.library.activeId && e.pending > 0);

    // Yatayda üç düğme sola geçince menünün içeriği onların altında kalmasın;
    // menü de o kadar genişler (yoksa satırlar kırılıyordu).
    final sideInset = MediaQuery.paddingOf(context).left;
    return Drawer(
      width: 304 + sideInset,
      child: ListView(
        padding: EdgeInsets.only(left: sideInset),
        children: [
          Padding(
            // Kenardan kenara çizimde durum çubuğunun altında kalmasın.
            padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + 10, 12, 6),
            // Envanterler buradan açılır (ada da dokunulur): menüde ayrıca bir "Envanterler" satırı
            // vardı, aynı sayfaya giden ikinci yol listeyi uzatıyordu.
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: host == null ? null : () => push(const InventoriesPage()),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                child: Row(
                  children: [
                    // Renk ya da amblem seçildiyse adın önünde.
                    if (host != null && host.library.active.hasLook) ...[
                      InventoryEmblem(entry: host.library.active, size: 34, active: true),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        inventoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineMedium,
                      ),
                    ),
                    if (host != null)
                      IconButton(
                        icon: Badge(
                          isLabelVisible: pendingElsewhere,
                          smallSize: 9,
                          backgroundColor: tones.accent,
                          child: const Icon(Icons.unfold_more_rounded),
                        ),
                        tooltip: s.switchInventory,
                        onPressed: () => push(const InventoriesPage()),
                      ),
                  ],
                ),
              ),
            ),
          ),
          // Profil kartı.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Material(
              color: tones.raised,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => _editProfile(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _pickAvatar(context),
                        child: CircleAvatar(
                          radius: 26,
                          backgroundColor: tones.ink,
                          foregroundImage: avatar == null ? null : FileImage(avatar),
                          child: avatar == null ? Icon(Icons.person_rounded, color: tones.paper) : null,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settings.userName.isEmpty ? s.user : settings.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(fontSize: 19),
                            ),
                            Text(
                              sharing.enabled && sharing.config.isShared ? sharing.inventoryName : s.localInventory,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: s.editName,
                        onPressed: () => _editProfile(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (store.backupDue) const _BackupReminder(),
          // Destenin dört paneli (sağ kenardaki kulplarla aynı) tek satırda: dört ayrı satırdı, menü
          // telefonda kaydırmadan sığmıyordu. Tam adları ipucunda. Menü kapanırken bu bağlam hâlâ
          // ağaçta; kabuğun paneli açılır.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: kFixedTextScale,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, (icon, label, tooltip, count, tint, open)) in [
                    (Icons.inbox_rounded, s.drawer, s.drawer, drawerCount, null, InventoryShell.openDrawerPanel),
                    (
                      Icons.travel_explore_rounded,
                      s.lostShort,
                      s.lostItems,
                      lostCount,
                      lostCount == 0 ? null : tones.lost,
                      InventoryShell.openLostPanel,
                    ),
                    (
                      Icons.star_rounded,
                      s.menuFavorites,
                      s.favorites,
                      favoriteCount,
                      null,
                      InventoryShell.openFavoritesPanel,
                    ),
                    (
                      Icons.event_busy_rounded,
                      s.menuExpired,
                      s.expiredPanel,
                      expired,
                      expired == 0 ? null : tones.danger,
                      InventoryShell.openExpiredPanel,
                    ),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 6),
                    Expanded(
                      child: _PanelButton(
                        icon: icon,
                        label: label,
                        tooltip: tooltip,
                        count: count,
                        tint: tint,
                        onTap: () {
                          Navigator.of(context).pop();
                          open(context);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Son kullanma tarihi geçen ya da yaklaşanlar; garantiler de orada.
          _Tile(
            icon: Icons.event_note_rounded,
            label: s.datesPage,
            trailing: expiring == 0 ? null : '$expiring',
            tint: expiring == 0 ? null : tones.lost,
            onTap: () => push(const DatesPage()),
          ),
          // Tükenenler ve tarihi geçenler; metin olarak paylaşılır.
          _Tile(
            icon: Icons.shopping_cart_rounded,
            label: s.shoppingList,
            trailing: toBuy == 0 ? null : '$toBuy',
            tint: toBuy == 0 ? null : tones.accent,
            onTap: () => push(const ShoppingPage()),
          ),
          _Tile(
            icon: Icons.front_hand_rounded,
            label: s.borrowedPageTitle,
            trailing: borrowedCount == 0 ? null : '$borrowedCount',
            // Gecikmemiş emanette renk yok (öteki satırlar gibi): `tones.raised` açık temada simgeyi zeminle
            // aynı renge boyuyor, koyu temada sayıyı koyu zeminde okunmaz yapıyordu.
            tint: hasOverdueBorrow ? tones.danger : null,
            onTap: () => push(const LendingPage()),
          ),
          // Eşyaların değeri: toplam, yerlere göre, sigorta / taşınma dökümü.
          _Tile(
            icon: Icons.sell_outlined,
            label: s.valuePageTitle,
            onTap: () => push(const ValuePage()),
          ),
          _Tile(
            icon: Icons.fact_check_outlined,
            label: s.auditInventory,
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop();
              AuditPage.start(nav.context);
            },
          ),
          _Tile(
            icon: Icons.wifi_tethering_rounded,
            label: s.sharing,
            trailing: sharing.onlineMembers.isEmpty ? null : '${sharing.onlineMembers.length}',
            onTap: () => push(const SharingPage()),
          ),
          if (sharing.enabled || pending > 0)
            _Tile(
              icon: pending > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
              label: s.changes,
              trailing: pending == 0 ? null : '$pending',
              tint: pending == 0 ? null : tones.accent,
              onTap: () => push(const ChangesPage()),
            ),
          _Tile(
            icon: Icons.delete_outline_rounded,
            label: s.trash,
            trailing: trashCount == 0 ? null : '$trashCount',
            onTap: () => push(const TrashPage()),
          ),
          _Tile(
            icon: Icons.settings_rounded,
            label: s.settings,
            onTap: () => push(const SettingsPage()),
          ),
          Padding(
            // Sistem çubuğunun üstünde: kenardan kenara çizimde altında kalıyordu.
            padding: EdgeInsets.fromLTRB(28, 22, 28, 28 + bottomInset(context)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${store.visibleRecordCount}', style: theme.textTheme.displaySmall?.copyWith(height: 1)),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(s.totalRecords, style: theme.textTheme.bodySmall),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yedek alma zamanı geldiyse menünün başında sakin bir not: sunucu olmadığı
/// için telefon kaybolursa envanter de gider. "Sonra" bir hafta susturur.
class _BackupReminder extends StatelessWidget {
  const _BackupReminder();

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final never = store.settings.lastBackupAt == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 6),
        decoration: BoxDecoration(
          color: tones.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tones.accent.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.save_alt_rounded, size: 20, color: tones.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.backupReminderTitle,
                        style: TextStyle(
                          fontFamily: kDisplayFont,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: tones.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.backupReminderBody(store.changesSinceBackup, never: never),
                        style: TextStyle(fontSize: 12.5, height: 1.35, color: tones.ink),
                      ),
                      if (!never)
                        Text(
                          BackupFlows.lastBackupLabel(store),
                          style: TextStyle(fontSize: 12, color: tones.muted, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // Büyük yazı boyunda düğmeler alt alta geçsin, taşmasın.
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: tones.muted),
                    onPressed: () => store.snoozeBackupReminder(),
                    child: Text(s.later),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: tones.accent),
                    onPressed: () {
                      Navigator.of(context).pop();
                      BackupFlows.export(context);
                    },
                    child: Text(s.backupNow, style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.tint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailing;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        // Biraz sık (56 yerine 48 dp): dokunma payı yine yeterli, menü bir ekrana sığar.
        visualDensity: const VisualDensity(vertical: -2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tint?.withValues(alpha: 0.16) ?? tones.raised,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: tint ?? tones.ink),
        ),
        title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: tones.ink)),
        trailing: trailing == null
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(color: tint ?? tones.ink, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  trailing!,
                  style: TextStyle(
                    color: tint == null ? tones.paper : kInk,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
        onTap: onTap,
      ),
    );
  }
}

/// Destenin bir paneli (çekmece, kayıp, sık kullanılan, tarihi geçen): simge, altında kısa ad,
/// simgenin köşesinde sayısı. Odak katmanındaki hızlı düğmeler gibi; tam adı ipucunda.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.count,
    required this.onTap,
    this.tint,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final int count;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final color = tint ?? tones.ink;
    final scale = (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, kFixedTextScale);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tones.raised,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  backgroundColor: tint ?? tones.ink,
                  textColor: tint == null ? tones.paper : kInk,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: tint?.withValues(alpha: 0.16) ?? tones.paper,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 19, color: color),
                  ),
                ),
                const SizedBox(height: 6),
                // İki satıra kadar ("Sık kullanılan" dar menüde bölünür).
                SizedBox(
                  height: 30 * scale,
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w700, color: tones.ink),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
