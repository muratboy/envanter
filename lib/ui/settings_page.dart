import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../data/settings.dart';
import '../state/inventory_host.dart';
import '../state/inventory_store.dart';
import 'backup_flows.dart';
import 'inventories_page.dart';
import 'node_list_view.dart';
import '../services/date_notifier.dart';
import 'widgets/currency_picker.dart';
import 'widgets/date_fields.dart';
import 'sharing/sharing_flows.dart';
import 'sharing/sharing_page.dart';
import 'sharing/sharing_scope.dart';
import 'widgets/entrance.dart';
import 'widgets/paper.dart';
import 'shell.dart';
import 'storage_page.dart';

/// Ayarlar iki sekmede: **Bana ait** (görünüm, dil, otomatik yedek: bütün
/// envanterlerde aynı) ve **Bu envanter** (deste, konum, tarihler, ortak
/// kullanım, dışa/içe aktarma). Eskiden sekiz bölüm tek uzun sayfadaydı ve
/// hangisinin kime ait olduğu yalnızca ortadaki bir başlıktan anlaşılıyordu.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// Son bakılan sekme: ayarlara yeniden girince aynı yerden devam edilsin.
  static bool _lastInventoryTab = false;

  late bool _inventoryTab = _lastInventoryTab;

  void _show(bool inventory) {
    _lastInventoryTab = inventory;
    setState(() => _inventoryTab = inventory);
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final sharing = SharingScope.of(context);
    final s = store.strings;
    final settings = store.settings;
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final host = LibraryScope.maybeOf(context);

    return Scaffold(
      appBar: ShellHeader(
        title: s.settings,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: s.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // Sekmeler başlığın altında sabit durur; içerik altında kayar.
          ReadableWidth(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(s.settingsMine),
                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(s.settingsInventory),
                      icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    ),
                  ],
                  selected: {_inventoryTab},
                  onSelectionChanged: (v) => _show(v.single),
                ),
              ),
            ),
          ),
          Expanded(
            // Sekme değişince içerik geldiği yönden hafifçe kayarak belirir.
            child: Entrance(
              trigger: _inventoryTab,
              fadeFrom: 0.35,
              offset: Offset(_inventoryTab ? 20 : -20, 0),
              child: ListView(
              // Sekme değişince liste baştan başlasın.
              key: ValueKey(_inventoryTab),
              padding: EdgeInsets.only(bottom: 40 + bottomInset(context)),
              children: [
                ReadableWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _inventoryTab
                        ? [
                          // Açık envanterin kendi ayarları; başında adı (değiştirilebilir).
                          if (host != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          s.thisInventoryTitle(host.nameOf(host.library.active, s)),
                                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: s.renameInventory,
                                        onPressed: () => InventoriesPage.rename(context, host.library.active),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(s.thisInventoryHint, style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                          PaperSection(
                            title: s.deckSection,
                            children: [
                              // Deste sırası: ayrı gruplar ya da tek sıra.
                              PaperRow(
                                icon: settings.groupKinds
                                    ? Icons.splitscreen_rounded
                                    : Icons.view_agenda_outlined,
                                title: s.groupKindsTitle,
                                subtitle: s.groupKindsHint,
                                onTap: () => store.updateSettings(
                                  settings.copyWith(groupKinds: !settings.groupKinds),
                                ),
                                trailing: Switch(
                                  value: settings.groupKinds,
                                  onChanged: (v) => store.updateSettings(settings.copyWith(groupKinds: v)),
                                ),
                              ),
                              const PaperDivider(),
                              // Görünüm: deste, liste (kalabalık envanterde) ya da ızgara.
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                                child: Text(s.viewTitle, style: theme.textTheme.titleMedium),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                                child: Text(s.viewHint, style: theme.textTheme.bodySmall),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                child: _Choices<DeckView>(
                                  value: settings.deckView,
                                  onChanged: (view) => store.updateSettings(settings.copyWith(deckView: view)),
                                  options: [
                                    for (final view in DeckView.values) (view, viewIcon(view), viewLabel(s, view)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          PaperSection(
                            title: s.location,
                            children: [
                              PaperRow(
                                icon: Icons.my_location_rounded,
                                title: s.autoLocationTitle,
                                subtitle: s.autoLocationSubtitle,
                                onTap: () => store.updateSettings(
                                  settings.copyWith(autoLocationOnCreate: !settings.autoLocationOnCreate),
                                ),
                                trailing: Switch(
                                  value: settings.autoLocationOnCreate,
                                  onChanged: (v) => store.updateSettings(settings.copyWith(autoLocationOnCreate: v)),
                                ),
                              ),
                            ],
                          ),
                          PaperSection(
                            title: s.datesSection,
                            children: [
                              // Genel uyarı süresi; eşya kendi süresini verebilir.
                              PaperRow(
                                icon: Icons.notifications_active_outlined,
                                title: s.expiryWarnSetting,
                                subtitle: s.expiryWarnGeneralHint(s.spanText(settings.expiryWarning)),
                                footnote: s.spanText(settings.expiryWarning),
                                onTap: () async {
                                  final choice = await pickSpan(
                                    context,
                                    title: s.expiryWarnSetting,
                                    current: settings.expiryWarning,
                                    allowClear: false,
                                  );
                                  final span = choice?.span;
                                  if (span == null) return;
                                  await store.updateSettings(store.settings.copyWith(expiryWarning: span));
                                },
                              ),
                              const PaperDivider(),
                              // Telefon bildirimi; açılınca izin istenir, izin yoksa söylenir.
                              ValueListenableBuilder<bool?>(
                                valueListenable: DateNotifier.instance.permitted,
                                builder: (context, permitted, _) {
                                  final denied = settings.dateNotifications && permitted == false;
                                  return PaperRow(
                                    icon: Icons.notifications_rounded,
                                    title: s.notifySetting,
                                    subtitle: s.notifySettingHint,
                                    footnote: denied ? s.notifyDenied : null,
                                    tint: denied ? tones.danger : null,
                                    onTap: denied ? () => DateNotifier.instance.requestPermission() : null,
                                    trailing: Switch(
                                      value: settings.dateNotifications,
                                      onChanged: (on) async {
                                        await store.updateSettings(store.settings.copyWith(dateNotifications: on));
                                        if (on) await DateNotifier.instance.requestPermission();
                                      },
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          // Yeni fiyatların birimi (eşyanın kendi fiyatı birimiyle saklanır).
                          PaperSection(
                            title: s.valueSection,
                            children: [
                              PaperRow(
                                icon: Icons.sell_outlined,
                                title: '${s.currency}: ${currencyLabel(settings.defaultCurrency)}',
                                subtitle: s.currencyHint,
                                onTap: () async {
                                  final code = await pickCurrency(context, selected: settings.defaultCurrency);
                                  if (code == null) return;
                                  await store.updateSettings(store.settings.copyWith(currency: code));
                                },
                              ),
                            ],
                          ),
                          PaperSection(
                            title: s.sharing,
                            children: [
                              PaperRow(
                                icon: Icons.wifi_tethering_rounded,
                                title: s.sharing,
                                subtitle: sharing.enabled ? sharing.inventoryName : s.sharingOffTitle,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => const SharingPage()),
                                ),
                              ),
                              const PaperDivider(),
                              PaperRow(
                                icon: Icons.bolt_rounded,
                                title: s.autoAcceptTitle,
                                subtitle: s.autoAcceptSubtitle,
                                onTap: () => SharingFlows.setAutoAccept(context, !sharing.config.autoAccept),
                                trailing: Switch(
                                  value: sharing.config.autoAccept,
                                  onChanged: (v) => SharingFlows.setAutoAccept(context, v),
                                ),
                              ),
                            ],
                          ),
                          PaperSection(
                            title: s.inventory,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                child: Row(
                                  children: [
                                    _Stat(value: store.visibleRecordCount, label: s.recordTotal),
                                    Container(width: 1, height: 44, color: tones.line),
                                    _Stat(value: store.trash.length, label: s.inTrash),
                                  ],
                                ),
                              ),
                              const PaperDivider(),
                              // Fotoğrafların ve eklerin kapladığı yer; dokununca en büyük ekler.
                              const _StorageRow(),
                              const PaperDivider(),
                              // Yedek: her şey tek dosyada; yeni telefona da böyle taşınır.
                              PaperRow(
                                icon: Icons.ios_share_rounded,
                                title: s.exportTitle,
                                subtitle: s.exportHint,
                                footnote: BackupFlows.lastBackupLabel(store),
                                tint: store.backupDue ? tones.accent : null,
                                onTap: () => BackupFlows.export(context),
                              ),
                              const PaperDivider(),
                              PaperRow(
                                icon: Icons.download_rounded,
                                title: s.importTitle,
                                subtitle: s.importHint,
                                onTap: () => BackupFlows.import(context),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(26, 18, 26, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.lock_outline_rounded, size: 16, color: tones.muted),
                                const SizedBox(width: 8),
                                Expanded(child: Text(s.localOnly, style: theme.textTheme.bodySmall)),
                              ],
                            ),
                          ),
                          ]
                        : [
                          PaperSection(
                            title: s.appearance,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: _Choices<ThemeMode>(
                                  value: settings.themeMode,
                                  onChanged: (mode) => store.updateSettings(settings.copyWith(themeMode: mode)),
                                  options: [
                                    (ThemeMode.system, Icons.brightness_auto_rounded, s.systemTheme),
                                    (ThemeMode.light, Icons.light_mode_rounded, s.lightTheme),
                                    (ThemeMode.dark, Icons.dark_mode_rounded, s.darkTheme),
                                  ],
                                ),
                              ),
                              const PaperDivider(),
                              // Kişisel: bütün envanterlerde aynı.
                              PaperRow(
                                icon: Icons.screen_rotation_rounded,
                                title: s.rotateTitle,
                                subtitle: s.rotateHint,
                                onTap: () => _setRotate(store, !settings.rotateScreen),
                                trailing: Switch(
                                  value: settings.rotateScreen,
                                  onChanged: (on) => _setRotate(store, on),
                                ),
                              ),
                            ],
                          ),
                          PaperSection(
                            title: s.language,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: _Choices<AppLanguage>(
                                  value: settings.language,
                                  onChanged: (lang) => store.updateSettings(settings.copyWith(language: lang)),
                                  options: [
                                    (AppLanguage.system, Icons.translate_rounded, s.languageSystem),
                                    (AppLanguage.turkish, Icons.language_rounded, 'Türkçe'),
                                    (AppLanguage.english, Icons.language_rounded, 'English'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Kapalı envanterlerin arka planda eşitlenmesi (yalnızca birden
                          // çok envanter olabilen kurulumda; varsayılan açık).
                          if (host != null)
                            PaperSection(
                              title: s.sharing,
                              children: [
                                PaperRow(
                                  icon: Icons.sync_rounded,
                                  title: s.syncClosedTitle,
                                  subtitle: s.syncClosedHint,
                                  onTap: () => store.updateSettings(settings.copyWith(syncClosed: !settings.syncClosed)),
                                  trailing: Switch(
                                    value: settings.syncClosed,
                                    onChanged: (on) => store.updateSettings(settings.copyWith(syncClosed: on)),
                                  ),
                                ),
                                const PaperDivider(),
                                // Onay bekleyen yeni değişiklik için telefon bildirimi; tarih
                                // bildirimiyle aynı izin, yoksa söylenir.
                                ValueListenableBuilder<bool?>(
                                  valueListenable: DateNotifier.instance.permitted,
                                  builder: (context, permitted, _) {
                                    final denied = settings.notifyPending && permitted == false;
                                    return PaperRow(
                                      icon: Icons.notifications_active_rounded,
                                      title: s.notifyPendingTitle,
                                      subtitle: s.notifyPendingHint,
                                      footnote: denied ? s.notifyDenied : null,
                                      tint: denied ? tones.danger : null,
                                      onTap: denied ? () => DateNotifier.instance.requestPermission() : null,
                                      trailing: Switch(
                                        value: settings.notifyPending,
                                        onChanged: (on) async {
                                          await store.updateSettings(store.settings.copyWith(notifyPending: on));
                                          if (on) await DateNotifier.instance.requestPermission();
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          // Otomatik yedek kişisel: bütün envanterler aynı klasöre, kendi adlarıyla.
                          PaperSection(
                            title: s.backupSection,
                            children: [
                              // Haftada bir ve değişen envanterden çıkarken; dokununca klasör değişir.
                              PaperRow(
                                icon: Icons.backup_rounded,
                                title: s.autoBackupTitle,
                                subtitle: settings.autoBackupFolder == null
                                    ? s.autoBackupHint
                                    : s.autoBackupOn(settings.autoBackupFolder!),
                                footnote: settings.autoBackupFailedAt == null ? null : s.autoBackupFailed,
                                tint: settings.autoBackupFailedAt == null ? null : tones.danger,
                                onTap: () => BackupFlows.chooseAutoFolder(context),
                                trailing: Switch(
                                  value: settings.autoBackupUri != null,
                                  onChanged: (on) =>
                                      on ? BackupFlows.chooseAutoFolder(context) : BackupFlows.disableAuto(context),
                                ),
                              ),
                            ],
                          ),
                          ],
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Fotoğraflar ve ekler: 128 fotoğraf · 12 ek dosyası — 340 MB". Dosyalara tek
/// tek bakıldığı için sayfa açılınca (ve kayıtlar değişince) bir kez ölçülür;
/// her çizimde değil.
class _StorageRow extends StatefulWidget {
  const _StorageRow();

  @override
  State<_StorageRow> createState() => _StorageRowState();
}

class _StorageRowState extends State<_StorageRow> {
  Future<StorageUsage>? _usage;
  (int, int, int)? _measuredAt;

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    // Kayıt sayısı da: içe aktarma ve eşitleme yerel sayaç artırmaz ama dosya getirir
    // (içe aktarmadan sonra satır "0 B"de kalıyordu).
    final revision = (store.localRevision.value, store.visibleRecordCount, store.trash.length);
    if (_usage == null || _measuredAt != revision) {
      _measuredAt = revision;
      _usage = store.measureStorage();
    }
    return FutureBuilder<StorageUsage>(
      future: _usage,
      builder: (context, snap) {
        final usage = snap.data;
        return PaperRow(
          icon: Icons.pie_chart_outline_rounded,
          title: s.storageTitle,
          subtitle: usage == null ? s.storageMeasuring : s.storageSummary(usage.photoCount, usage.fileCount),
          footnote: usage == null ? null : s.fileSize(usage.totalBytes),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StoragePage())),
        );
      },
    );
  }
}

Future<void> _setRotate(InventoryStore store, bool on) async {
  await store.updateSettings(store.settings.copyWith(rotateScreen: on));
  await applyOrientation(rotate: on);
}

/// Yan yana seçenek kutucukları (tema, dil); seçili olan mürekkeple çizili.
class _Choices<T> extends StatelessWidget {
  const _Choices({required this.value, required this.onChanged, required this.options});

  final T value;
  final ValueChanged<T> onChanged;
  final List<(T, IconData, String)> options;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return Row(
      children: [
        for (final (i, (v, icon, label)) in options.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: v == value ? tones.ink : tones.raised,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                  child: Column(
                    children: [
                      Icon(icon, size: 22, color: v == value ? tones.paper : tones.ink),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: v == value ? tones.paper : tones.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: theme.textTheme.headlineMedium?.copyWith(fontSize: 30)),
          const SizedBox(height: 2),
          Text(label, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
