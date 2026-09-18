import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/money.dart';
import '../core/strings.dart';
import '../core/transitions.dart';
import '../data/node.dart';
import '../core/app_paths.dart';
import '../services/image_service.dart';
import '../services/location_service.dart';
import '../services/qr_service.dart';
import '../services/visual_index.dart';
import '../state/inventory_store.dart';
import '../sync/fields.dart';
import '../core/time_span.dart';
import '../services/date_notifier.dart';
import 'widgets/attachments.dart';
import 'widgets/currency_picker.dart';
import 'widgets/date_fields.dart';
import 'widgets/location_sheet.dart';
import 'widgets/node_card.dart';
import 'widgets/qr_sheet.dart';
import 'widgets/tree_picker.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import 'scan_page.dart';
import 'shell.dart';
import 'widgets/paper.dart';
import 'widgets/text_prompt.dart';
import '../services/image_tone.dart';
import 'widgets/icon_picker_sheet.dart';
import 'sharing/manager_picker.dart';
import 'sharing/sharing_scope.dart';
import '../data/lots.dart';

/// Düzenleyicinin istenince açılan bölümleri.
enum _Section { quantity, shopping, dates, value, service, attachments, more }

/// Kart buyuyerek edit moduna gecer. Tik'e basilana kadar hicbir sey
/// diske yazilmaz; yeni kayıtlar vazgecilirse iz bırakmaz.
class NodeEditorPage extends StatefulWidget {
  const NodeEditorPage({super.key, required this.node, required this.isNew});

  final Node node;
  final bool isNew;

  @override
  State<NodeEditorPage> createState() => _NodeEditorPageState();
}

class _NodeEditorPageState extends State<NodeEditorPage> {
  late Node _draft = widget.node;

  /// "Yalnızca bende" işareti; kaydedince yazılır.
  late bool _private = InventoryScope.read(context).isPrivateRoot(widget.node.id);
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.isNew && widget.node.isContainer ? '' : widget.node.name);
  late final String? _originalImage = widget.node.imagePath;

  /// Açık bölümler. Yeni eşyada yedi bölüm alt alta geliyordu; çoğu kayıtta
  /// adet, tarih, ek girilmez. Her kayıtta bakılanlar (görünüm, yer, not) hep
  /// açık; ötekiler altta birer düğme olarak durur, dokununca açılır. İçinde
  /// bilgi olan bölüm açık gelir; açılan bölüm sayfa kapanana dek açık kalır.
  late final Set<_Section> _open = {
    if (widget.node.tracksQuantity) _Section.quantity,
    if (widget.node.autoShop) _Section.shopping,
    if (widget.node.hasDates ||
        widget.node.hasLots ||
        widget.node.shelfLife != null ||
        widget.node.warranty != null ||
        widget.node.expiryWarn != null)
      _Section.dates,
    if (widget.node.price != null || widget.node.serial != null) _Section.value,
    if (widget.node.hasService) _Section.service,
    if (widget.node.hasAttachments) _Section.attachments,
    if (widget.node.barcode != null || widget.node.isBorrowed) _Section.more,
  };

  /// Fiyat yazılırken kullanılacak birim: kaydın kendi birimi, yoksa envanterin varsayılanı.
  late String _currency =
      widget.node.priceMoney?.currency ?? InventoryScope.read(context).settings.defaultCurrency;

  final Map<_Section, GlobalKey> _sectionKeys = {for (final x in _Section.values) x: GlobalKey()};

  /// Bölüm bu türde var mı (adet, alışveriş ve tarihler yalnızca eşyada).
  bool _applies(_Section x) => switch (x) {
        _Section.quantity || _Section.shopping || _Section.dates || _Section.value => !_draft.isContainer,
        // Bakım klasörde de olur (araba, akvaryum).
        _Section.service || _Section.attachments || _Section.more => true,
      };

  bool _shows(_Section x) => _applies(x) && _open.contains(x);

  void _openSection(_Section x) {
    setState(() => _open.add(x));
    // Açılan bölüm görünür yere gelsin (düğmelerin üstünde, başka bölümlerin arasında açılabilir).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final at = _sectionKeys[x]!.currentContext;
      if (at == null || !at.mounted) return;
      Scrollable.ensureVisible(at, alignment: 0.15, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    });
  }

  /// Kapalı bölümlerin düğmeleri; hepsi açıksa hiçbir şey.
  Widget _moreChips(AppStrings s) {
    final closed = [
      for (final x in _Section.values)
        if (_applies(x) && !_open.contains(x)) x,
    ];
    if (closed.isEmpty) return const SizedBox.shrink();
    return PaperSection(
      title: s.moreFields,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final x in closed)
                ActionChip(
                  avatar: Icon(
                    switch (x) {
                      _Section.quantity => Icons.inventory_rounded,
                      _Section.shopping => Icons.add_shopping_cart_rounded,
                      _Section.dates => Icons.event_outlined,
                      _Section.value => Icons.sell_outlined,
                      _Section.service => Icons.build_outlined,
                      _Section.attachments => Icons.attach_file_rounded,
                      _Section.more => Icons.tune_rounded,
                    },
                    size: 18,
                  ),
                  label: Text(switch (x) {
                    _Section.quantity => s.quantity,
                    _Section.shopping => s.shoppingList,
                    _Section.dates => s.datesSection,
                    _Section.value => s.valueSection,
                    _Section.service => s.serviceSection,
                    _Section.attachments => s.attachments,
                    _Section.more => s.moreActions,
                  }),
                  onPressed: () => _openSection(x),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Kayıtta zaten duran eklerin dosyaları: taslaktan çıkarılsa da kaydedilene
  /// dek silinmez (vazgeçilirse kayıt eskisi gibi kalmalı).
  late final Set<String> _originalFiles = {for (final a in widget.node.attachments) ?a.file};

  /// Ad boş bırakılırsa alacağı ad; başlıkta silik ipucu (bir kez hesaplanır).
  late final String _unnamedHint = InventoryScope.read(context).nextUnnamed(except: widget.node.id);
  bool _saving = false;
  bool _locating = false;

  bool _autoLocateChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_autoLocateChecked) return;
    _autoLocateChecked = true;
    // Ayar aciksa yeni klasöre konumu kendiliğinden ekle.
    final store = InventoryScope.read(context);
    if (widget.isNew &&
        store.settings.autoLocationOnCreate &&
        widget.node.isContainer &&
        !widget.node.hasGeo) {
      _autoLocate(silent: true);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoLocate({bool silent = false}) async {
    setState(() => _locating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await LocationService.current();
      if (!mounted) return;
      setState(() => _draft = _draft.copyWith(
            lat: result.lat,
            lng: result.lng,
            locationLabel: result.label ?? _draft.locationLabel,
          ));
    } on LocationFailure catch (e) {
      if (!silent) {
        final s = InventoryScope.read(context).strings;
        messenger.showSnackBar(SnackBar(
          content: Text(switch (e) {
            LocationFailure.serviceOff => s.locationServiceOff,
            LocationFailure.denied => s.locationDenied,
            LocationFailure.deniedForever => s.locationDeniedForever,
            LocationFailure.unknown => s.locationFailed,
          }),
        ));
      }
    } on Exception {
      if (!silent) {
        messenger.showSnackBar(
          SnackBar(content: Text(InventoryScope.read(context).strings.locationFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Kullanıcı bu oturumda rengi kendisi seçti; fotoğraf onu değiştirmez.
  bool _colorChosen = false;

  Future<void> _pickImage() async {
    final s = AppStrings.of(context);
    final choice = await showAppSheet<String>(context, (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(s.takePhoto),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(s.pickFromGallery),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            if (_draft.hasImage)
              ListTile(
                leading: const Icon(Icons.hide_image_rounded),
                title: Text(s.removePhoto),
                onTap: () => Navigator.of(context).pop('remove'),
              ),
            const SizedBox(height: 12),
          ],
        ),
      );
    });
    if (choice == null || !mounted) return;

    if (choice == 'remove') {
      // Yeni çekilmiş ama kaydedilmemiş resmi diskten de sil.
      if (_draft.imagePath != _originalImage) ImageService.discard(_draft.imagePath);
      setState(() => _draft = _draft.copyWith(clearImage: true, clearSignature: true));
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await ImageService.pick(
        choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      );
      if (path == null || !mounted) return;
      final previous = _draft.imagePath;
      if (previous != null && previous != _originalImage) ImageService.discard(previous);
      setState(() => _draft = _draft.copyWith(imagePath: path, clearSignature: true));

      final file = AppPaths.imageFile(path);
      if (file == null) return;
      // Kart rengi elle seçilmediyse fotoğrafın tonuna uysun.
      if (!_colorChosen) {
        final tone = await ImageTone.paletteMatch(file);
        if (tone != null && mounted && _draft.imagePath == path && !_colorChosen) {
          setState(() => _draft = _draft.copyWith(color: tone.toARGB32()));
        }
      }

      // Görüntüyle arama için parmak izi; arayüzü bekletmeye gerek yok.
      final signature = await VisualIndex.signatureOf(file);
      if (signature == null || !mounted) return;
      if (_draft.imagePath != path) return; // bu arada değişmişse dokunma
      setState(() => _draft = _draft.copyWith(imageSig: signature.encode()));
    } on Exception {
      messenger.showSnackBar(SnackBar(content: Text(s.photoFailed)));
    }
  }

  Future<void> _addAttachments() async {
    final added = await pickAttachments(context, existing: _draft.attachments);
    if (added.isEmpty) return;
    if (!mounted) {
      // Sayfa bu arada kapandıysa dosyalar sahipsiz kalmasın.
      for (final a in added) {
        ImageService.discard(a.file);
      }
      return;
    }
    setState(() => _draft = _draft.copyWith(attachments: [..._draft.attachments, ...added]));
  }

  void _removeAttachment(Attachment a) {
    // Bu oturumda eklenip kaydedilmemiş dosya hemen silinir; kayıttaki ek
    // kaydedince (bkz. [_save]).
    if (a.file case final rel? when !_originalFiles.contains(rel)) ImageService.discard(rel);
    setState(() => _draft = _draft.copyWith(attachments: [
          for (final x in _draft.attachments)
            if (x.id != a.id) x,
        ]));
  }

  /// Kullanım kılavuzu, garanti belgesi, video, bağlantı: klasörde de eşyada da.
  Widget _attachmentsSection(AppStrings s) {
    final tones = Tones.of(context);
    final list = _draft.attachments;
    return PaperSection(
      title: s.attachments,
      children: [
        for (final (i, a) in list.indexed) ...[
          if (i > 0) const PaperDivider(),
          AttachmentRow(
            key: ValueKey(a.id),
            attachment: a,
            onRename: (name) => setState(() => _draft = _draft.copyWith(attachments: [
                  for (final x in _draft.attachments) x.id == a.id ? x.renamed(name) : x,
                ])),
            onRemove: () => _removeAttachment(a),
          ),
        ],
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Text(s.attachmentsHint, style: TextStyle(fontSize: 12.5, color: tones.muted, height: 1.3)),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 16, 6),
            child: TextButton.icon(
              onPressed: _addAttachments,
              icon: const Icon(Icons.attach_file_rounded, size: 18),
              label: Text(s.addAttachment),
            ),
          ),
        ),
      ],
    );
  }

  /// Ortak kullanımda klasörün sorumluları. Atamayı ana kullanıcılar
  /// yapar; diğerleri yalnızca kimin sorumlu olduğunu görür.
  Widget? _managersRow(BuildContext context) {
    final sharing = SharingScope.maybeOf(context);
    if (sharing == null || !sharing.config.isShared) return null;
    final s = AppStrings.of(context);
    final names = [for (final id in _draft.managers) sharing.memberName(id) ?? s.someone];
    final canAssign = sharing.config.isAdmin;
    if (!canAssign && names.isEmpty) return null;
    return PaperRow(
      icon: Icons.supervisor_account_rounded,
      title: names.isEmpty ? s.assignManager : s.managersLabel(names.join(', ')),
      subtitle: s.managerHint,
      onTap: canAssign ? _pickManagers : null,
    );
  }

  Future<void> _pickManagers() async {
    final sharing = SharingScope.read(context);
    final picked = await pickManagers(context, sharing: sharing, current: _draft.managers);
    if (picked == null || !mounted) return;
    setState(() => _draft = _draft.copyWith(managers: picked));
  }

  Future<void> _pickIcon() async {
    final key = await pickNodeIcon(
      context,
      kind: _draft.kind,
      current: _draft.icon,
      color: Color(_draft.color),
    );
    if (key == null || !mounted) return;
    setState(() => _draft = key.isEmpty
        ? _draft.copyWith(clearIcon: true)
        : _draft.copyWith(icon: key));
  }

  /// Klasörün konumu dünyadaki yeridir (GPS); eşyanın konumu ise
  /// hangi klasörde durduğudur.
  Future<void> _editGeoLocation() async {
    final edit = await showAppSheet<LocationEdit>(
      context,
      (_) => LocationSheet(node: _draft),
    );
    if (edit == null || !mounted) return;
    setState(() {
      _draft = edit.cleared
          ? _draft.copyWith(clearGeo: true)
          : _draft.copyWith(lat: edit.lat, lng: edit.lng, locationLabel: edit.label);
    });
  }

  Future<void> _editPlacement() async {
    final target = await pickTreeTarget(context, moving: _draft);
    if (target == null || !mounted) return;
    final toRoot = Roots.isVirtual(target);
    setState(() {
      _draft = _draft.copyWith(
        parentId: toRoot ? null : target,
        clearParent: toRoot,
        inDrawer: target == Roots.drawer,
      );
    });
  }

  /// Tarih satırı: dokununca takvim, doluysa sağda sil.
  Widget _dayRow({
    required IconData icon,
    required String title,
    required DateTime? value,
    required ValueChanged<DateTime?> onChanged,
    String? extra,
    Color? tint,
  }) {
    final s = InventoryScope.of(context).strings;
    return PaperRow(
      icon: icon,
      title: title,
      subtitle: value == null ? s.notSet : [s.formatDate(value), ?extra].join(' · '),
      tint: tint,
      onTap: () async {
        final picked = await pickDay(context, initial: value);
        if (picked != null) onChanged(picked);
      },
      trailing: value == null
          ? null
          : IconButton(
              tooltip: s.clearValue,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => onChanged(null),
            ),
    );
  }

  /// Süre satırı ("3 ay"); altında ne işe yaradığı ya da hesaplanan tarih.
  Widget _spanRow({
    required IconData icon,
    required String title,
    required String? value,
    required String detail,
    required ValueChanged<TimeSpan?> onChanged,
    String? hint,
    String? emptyLabel,
    String? clearLabel,
  }) {
    final s = InventoryScope.of(context).strings;
    final span = TimeSpan.parse(value);
    return PaperRow(
      icon: icon,
      title: title,
      subtitle: detail,
      footnote: span == null ? (emptyLabel ?? s.notSet) : s.spanText(span),
      onTap: () async {
        final choice = await pickSpan(context, title: title, current: span, hint: hint, clearLabel: clearLabel);
        if (choice != null) onChanged(choice.span);
      },
    );
  }

  /// Farklı tarihli paket: kaç tane, sonra tarihi.
  Future<void> _addLot() async {
    final s = AppStrings.of(context);
    final values = await showTextPrompt(
      context,
      title: s.addLotButton,
      fields: [PromptField(label: s.quantity, initial: '1', keyboardType: TextInputType.number, selectAll: true)],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    final count = int.tryParse(values?.single.trim() ?? '');
    if (count == null || count <= 0 || !mounted) return;
    final date = await pickDay(context, initial: _draft.lastExpiry, help: s.newLotsDate);
    if (date == null || !mounted) return;
    setState(() => _draft = addLot(_draft, count, date));
  }

  Widget _datesSection(InventoryStore store) {
    final s = store.strings;
    final tones = Tones.of(context);
    final d = _draft;
    final expiry = d.effectiveExpiry;
    final state = store.expiryOf(d);
    final stateTint = switch (state) {
      ExpiryState.expired => tones.danger,
      ExpiryState.soon => tones.lost,
      _ => null,
    };
    // Süreden hesaplanan tarihin açıklaması: tarih yazılıysa kullanılmaz,
    // satın alma yoksa hesaplanamaz.
    String derived(String? span, DateTime? explicit, DateTime? result, String hint) =>
        !TimeSpan.isValid(span)
            ? hint
            : explicit != null
                ? s.dateOverrides
                : result == null
                    ? s.needsPurchaseDate
                    : s.calculated(s.formatDate(result));
    void set(Node Function(Node n) change) => setState(() => _draft = change(_draft));

    return PaperSection(
      title: s.datesSection,
      children: [
        _dayRow(
          icon: Icons.shopping_bag_outlined,
          title: s.purchaseDate,
          value: d.purchasedAt,
          onChanged: (v) => set((n) => n.copyWith(purchasedAt: v, clearPurchased: v == null)),
        ),
        const PaperDivider(),
        // Farklı tarihli paketler: her biri adediyle ve tarihiyle ayrı satır
        // (tarihe dokununca değişir, adet 0 olunca paket kalkar).
        if (d.hasLots)
          for (final (i, lot) in d.lots.indexed) ...[
            if (i > 0) const PaperDivider(),
            PaperRow(
              icon: Icons.event_busy_outlined,
              title: i == 0 ? s.expiryDates : s.expiryOn(s.formatDate(lot.expires)),
              subtitle: [
                if (i == 0) s.expiryOn(s.formatDate(lot.expires)),
                dueText(s, lot.expires),
              ].join(' · '),
              tint: switch (expiryStateOf(lot.expires, store.warnSpanOf(d), DateTime.now())) {
                ExpiryState.expired => tones.danger,
                ExpiryState.soon => tones.lost,
                _ => null,
              },
              onTap: () async {
                final picked = await pickDay(context, initial: lot.expires);
                if (picked != null) set((n) => redateLot(n, i, picked));
              },
              trailing: _QuantityField(
                value: lot.count,
                tracked: true,
                onChanged: (c) => set((n) => setLotCount(n, i, c)),
                onType: () => _typeNumber(
                  title: s.quantity,
                  initial: lot.count,
                  apply: (c) => setLotCount(_draft, i, c),
                ),
              ),
            ),
          ]
        else
          _dayRow(
            icon: Icons.event_busy_outlined,
            title: s.expiryDate,
            value: d.expiresAt,
            extra: d.expiresAt == null ? null : dueText(s, d.expiresAt!),
            tint: d.expiresAt == null ? null : stateTint,
            onChanged: (v) => set((n) => n.copyWith(expiresAt: v, clearExpires: v == null)),
          ),
        // Adetli ve tarihli eşyaya farklı tarihli paket (6 yoğurt: 2'si 5 Eki, 4'ü 12 Eki).
        if (d.tracksQuantity && d.effectiveExpiry != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 16, 6),
              child: TextButton.icon(
                onPressed: _addLot,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(s.addLotButton),
              ),
            ),
          ),
        const PaperDivider(),
        _spanRow(
          icon: Icons.spa_outlined,
          title: s.shelfLife,
          value: d.shelfLife,
          hint: s.shelfLifeHint,
          detail: derived(d.shelfLife, d.expiresAt, d.expiresAt == null ? expiry : null, s.shelfLifeHint),
          onChanged: (v) => set((n) => n.copyWith(shelfLife: v?.encode(), clearShelfLife: v == null)),
        ),
        const PaperDivider(),
        _spanRow(
          icon: Icons.notifications_active_outlined,
          title: s.warnBeforeExpiry,
          value: d.expiryWarn,
          detail: expiry == null ? s.expiryWarnSettingHint(s.spanText(store.warnSpanOf(d))) : dueText(s, expiry),
          emptyLabel: s.defaultWarn(s.spanText(store.settings.expiryWarning)),
          clearLabel: s.useDefault,
          onChanged: (v) => set((n) => n.copyWith(expiryWarn: v?.encode(), clearExpiryWarn: v == null)),
        ),
        const PaperDivider(),
        _dayRow(
          icon: Icons.verified_user_outlined,
          title: s.warrantyEnd,
          value: d.warrantyEndsAt,
          onChanged: (v) => set((n) => n.copyWith(warrantyEndsAt: v, clearWarrantyEnd: v == null)),
        ),
        const PaperDivider(),
        _spanRow(
          icon: Icons.shield_outlined,
          title: s.warrantyPeriod,
          value: d.warranty,
          hint: s.warrantyPeriodHint,
          detail: derived(d.warranty, d.warrantyEndsAt, d.warrantyEndsAt == null ? d.effectiveWarrantyEnd : null,
              s.warrantyPeriodHint),
          onChanged: (v) => set((n) => n.copyWith(warranty: v?.encode(), clearWarranty: v == null)),
        ),
      ],
    );
  }

  /// Geçmişin tamamı gösterilsin mi (önce en yeni beşi).
  bool _allServiceLog = false;

  /// Bakım: döngü, ne yapılacağı, son bakım günü ve geçmiş. "Bakım yapıldı" tek dokunuşu odak
  /// katmanında ve "Tarihi yaklaşanlar"da; burada geçmiş elle düzenlenir (eski bir bakım
  /// eklenir, not yazılır, yanlış kayıt silinir).
  Widget _serviceSection(InventoryStore store) {
    final s = store.strings;
    final tones = Tones.of(context);
    final d = _draft;
    final next = d.nextService;
    final tint = switch (d.serviceStateOn(DateTime.now())) {
      ExpiryState.expired => tones.danger,
      ExpiryState.soon => tones.lost,
      _ => null,
    };
    void set(Node Function(Node n) change) => setState(() => _draft = change(_draft));
    final shown = _allServiceLog ? d.serviceLog : d.serviceLog.take(5);
    return PaperSection(
      title: s.serviceSection,
      children: [
        _spanRow(
          icon: Icons.autorenew_rounded,
          title: s.serviceCycle,
          value: d.serviceEvery,
          hint: s.serviceCycleHint,
          detail: d.serviceEvery == null
              ? s.serviceCycleHint
              : next == null
                  ? s.serviceNeedsLast
                  : '${s.nextServiceOn(s.formatDate(next))} · ${serviceDueText(s, next)}',
          onChanged: (v) => set((n) => n.copyWith(
                serviceEvery: v?.encode(),
                clearServiceEvery: v == null,
                clearServiceTask: v == null,
                // Döngü ilk kurulurken son bakım bugün sayılır; hemen altında değiştirilebilir.
                servicedAt: v != null && n.servicedAt == null ? dateOnly(DateTime.now()) : null,
              )),
        ),
        if (d.serviceEvery != null) ...[
          const PaperDivider(),
          PaperRow(
            icon: Icons.build_outlined,
            title: d.serviceTask ?? s.serviceTaskTitle,
            subtitle: d.serviceTask == null ? s.serviceTaskHint : s.serviceTaskTitle,
            onTap: _typeServiceTask,
            trailing: d.serviceTask == null
                ? null
                : IconButton(
                    tooltip: s.clearValue,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => set((n) => n.copyWith(clearServiceTask: true)),
                  ),
          ),
        ],
        const PaperDivider(),
        _dayRow(
          icon: Icons.event_available_outlined,
          title: s.lastService,
          value: d.servicedAt,
          tint: tint,
          onChanged: (v) => set((n) => n.copyWith(servicedAt: v, clearServiced: v == null)),
        ),
        const PaperDivider(),
        PaperRow(
          icon: Icons.history_rounded,
          title: s.serviceHistory,
          subtitle: d.serviceLog.isEmpty ? s.serviceHistoryEmpty : null,
          trailing: TextButton.icon(
            onPressed: _addServiceEntry,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(s.serviceAddEntry),
          ),
        ),
        // En yeni önce; dokununca not, sağda sil.
        for (final e in shown)
          PaperRow(
            icon: Icons.check_circle_outline_rounded,
            title: s.formatDate(e.day),
            subtitle: e.note,
            onTap: () => _editServiceNote(e),
            trailing: IconButton(
              tooltip: s.serviceRemoveEntry,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => set((n) => n.copyWith(serviceLog: [
                    for (final x in n.serviceLog)
                      if (!identical(x, e)) x,
                  ])),
            ),
          ),
        if (!_allServiceLog && d.serviceLog.length > 5)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(52, 0, 16, 6),
              child: TextButton(
                onPressed: () => setState(() => _allServiceLog = true),
                child: Text(s.serviceShowAll(d.serviceLog.length)),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _typeServiceTask() async {
    final s = AppStrings.of(context);
    final values = await showTextPrompt(
      context,
      title: s.serviceTaskTitle,
      message: s.serviceTaskHint,
      fields: [PromptField(label: s.serviceTaskTitle, initial: _draft.serviceTask ?? '')],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values == null || !mounted) return;
    final task = Node.cleanServiceTask(values.single);
    setState(() => _draft = _draft.copyWith(serviceTask: task, clearServiceTask: task == null));
  }

  /// Geçmişe elle bir bakım: önce günü (bugün önerilir), sonra isteğe bağlı not. Son bakımdan
  /// yeniyse son bakım da o gün olur (sonraki bakım ondan sayılır).
  Future<void> _addServiceEntry() async {
    final s = AppStrings.of(context);
    final day = await pickDay(context, initial: DateTime.now(), help: s.serviceAddEntry);
    if (day == null || !mounted) return;
    final values = await showTextPrompt(
      context,
      title: s.serviceEntryNote,
      message: s.serviceEntryNoteHint,
      fields: [PromptField(label: s.serviceEntryNote)],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values == null || !mounted) return;
    final last = _draft.servicedAt;
    setState(() => _draft = _draft.copyWith(
          serviceLog: ServiceEntry.add(_draft.serviceLog, ServiceEntry(day, ServiceEntry.cleanNote(values.single))),
          servicedAt: last == null || day.isAfter(last) ? day : null,
        ));
  }

  Future<void> _editServiceNote(ServiceEntry entry) async {
    final s = AppStrings.of(context);
    final values = await showTextPrompt(
      context,
      title: s.formatDate(entry.day),
      message: s.serviceEntryNoteHint,
      fields: [PromptField(label: s.serviceEntryNote, initial: entry.note ?? '')],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values == null || !mounted) return;
    final rest = [
      for (final x in _draft.serviceLog)
        if (!identical(x, entry)) x,
    ];
    setState(() => _draft = _draft.copyWith(
          serviceLog: ServiceEntry.add(rest, ServiceEntry(entry.day, ServiceEntry.cleanNote(values.single))),
        ));
  }

  void _showQr() {
    // QR kodu kimliğe bağlıdır; adı da göstermek için taslağı kullanıyoruz.
    final preview = _draft.copyWith(name: _nameCtrl.text);
    showAppSheet(context, (_) => QrSheet(node: preview));
  }

  void _toggleKind() {
    final store = InventoryScope.read(context);
    if (_draft.isContainer && store.childCount(_draft.id) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(store.strings.containerHasChildren)),
      );
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        kind: _draft.isContainer ? NodeKind.item : NodeKind.container,
      );
    });
  }

  /// Barkodu taslağa koyar (boşsa kaldırır); başka bir eşyada da varsa söyler
  /// (aynı üründen iki yerde olabilir: engel değil, bilgi).
  void _setBarcode(String? raw) {
    final code = Node.cleanBarcode(raw);
    setState(() => _draft = _draft.copyWith(barcode: code, clearBarcode: code == null));
    if (code == null) return;
    final store = InventoryScope.read(context);
    final other = store.byBarcode(code).where((n) => n.id != _draft.id).firstOrNull;
    if (other == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(store.strings.barcodeAlsoOn(store.nameOf(other)))));
  }

  Future<void> _typeBarcode() async {
    final s = InventoryScope.read(context).strings;
    final hint = _draft.isContainer ? s.containerBarcodeHint : s.barcodeHint;
    final values = await showTextPrompt(
      context,
      title: s.barcode,
      message: hint,
      fields: [
        PromptField(
          label: s.barcode,
          initial: _draft.barcode ?? '',
          capitalization: TextCapitalization.none,
          keyboardType: TextInputType.visiblePassword,
        ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values != null && mounted) _setBarcode(values.single);
  }

  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<ScannedCode>(
      MaterialPageRoute(builder: (_) => const ScanPage(barcodeOnly: true)),
    );
    if (code?.barcode != null && mounted) _setBarcode(code!.barcode);
  }

  bool get _turkish => AppStrings.of(context).locale.languageCode == 'tr';

  /// Bir tanesinin fiyatı; boş bırakılırsa fiyat kalkar. Tutar dilin yazımıyla da başka
  /// yazımla da girilebilir ("1.250,50", "1250.5"; bkz. [Money.parseInput]).
  Future<void> _typePrice() async {
    final s = AppStrings.of(context);
    final values = await showTextPrompt(
      context,
      title: s.priceTitle,
      message: s.priceHint,
      fields: [
        PromptField(
          label: '${s.priceTitle} (${currencyLabel(_currency)})',
          initial: _draft.priceMoney?.inputText(turkish: _turkish) ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          selectAll: true,
        ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values == null || !mounted) return;
    if (values.single.trim().isEmpty) {
      setState(() => _draft = _draft.copyWith(clearPrice: true));
      return;
    }
    final money = Money.parseInput(values.single, _currency);
    if (money == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(s.priceInvalid)));
      return;
    }
    setState(() => _draft = _draft.copyWith(price: money.encode()));
  }

  /// Birim değişince yazılmış tutar aynı kalır, yalnızca birimi değişir (kur çevrimi yok).
  Future<void> _pickPriceCurrency() async {
    final code = await pickCurrency(context, selected: _currency);
    if (code == null || !mounted) return;
    setState(() {
      _currency = code;
      final price = _draft.priceMoney;
      if (price != null) _draft = _draft.copyWith(price: Money(price.cents, code).encode());
    });
  }

  Future<void> _typeSerial() async {
    final s = AppStrings.of(context);
    final values = await showTextPrompt(
      context,
      title: s.serialTitle,
      message: s.serialHint,
      fields: [
        PromptField(
          label: s.serialTitle,
          initial: _draft.serial ?? '',
          capitalization: TextCapitalization.characters,
          keyboardType: TextInputType.visiblePassword,
        ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    if (values == null || !mounted) return;
    final serial = Node.cleanSerial(values.single);
    setState(() => _draft = _draft.copyWith(serial: serial, clearSerial: serial == null));
  }

  /// Fiyat satırının alt yazısı: adet birden çoksa toplamı da söyler ("2 × 625 ₺ = 1.250 ₺").
  String _priceSubtitle(AppStrings s) {
    final price = _draft.priceMoney;
    final q = _draft.quantity;
    if (price == null) return s.priceHint;
    if (q == null || q == 1) return s.priceEach(s.money(price));
    return s.valueTimes(q, s.money(price), s.money(price.times(q)));
  }

  Widget _valueSection(AppStrings s) {
    final price = _draft.priceMoney;
    return PaperSection(
      title: s.valueSection,
      children: [
        PaperRow(
          icon: Icons.sell_outlined,
          title: price == null ? s.priceTitle : s.money(price),
          subtitle: _priceSubtitle(s),
          onTap: _typePrice,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: _pickPriceCurrency,
                child: Text(currencyLabel(_currency)),
              ),
              if (price != null)
                IconButton(
                  tooltip: s.clearValue,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _draft = _draft.copyWith(clearPrice: true)),
                ),
            ],
          ),
        ),
        PaperRow(
          icon: Icons.confirmation_number_outlined,
          title: _draft.serial ?? s.serialTitle,
          subtitle: _draft.serial == null ? s.serialHint : s.serialTitle,
          onTap: _typeSerial,
          trailing: _draft.serial == null
              ? null
              : IconButton(
                  tooltip: s.clearValue,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _draft = _draft.copyWith(clearSerial: true)),
                ),
        ),
      ],
    );
  }

  Future<void> _editBorrow() async {
    final s = AppStrings.of(context);
    final store = InventoryScope.read(context);
    final controller = TextEditingController(text: _draft.borrowedTo ?? '');
    DateTime? dueDate = _draft.returnDueAt;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final known = store.knownBorrowers;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Alttaki sistem çubuğu da düşülür (uygulama kenardan kenara çizilir) ve sığmazsa kayar: Kaydet
            // düğmesi çubuğun altında, yatayda ekranın dışında kalıyordu.
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _draft.isBorrowed ? s.borrowDetailsTitle : s.borrowAction,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: !_draft.isBorrowed,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: s.borrower,
                          hintText: s.borrowerHint,
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      if (known.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final name in known) ...[
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: ActionChip(
                                    label: Text(name),
                                    avatar: const Icon(Icons.person_rounded, size: 16),
                                    onPressed: () {
                                      controller.text = name;
                                      setSheetState(() {});
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(s.returnDueDate, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.calendar_today_rounded, size: 16),
                            label: Text(dueDate != null ? s.formatDate(dueDate!) : s.pickReturnDate),
                            backgroundColor: dueDate != null ? theme.colorScheme.primaryContainer : null,
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: dueDate ?? DateTime.now().add(const Duration(days: 7)),
                                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                                lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                              );
                              if (picked != null) {
                                setSheetState(() => dueDate = dateOnly(picked));
                              }
                            },
                          ),
                          ActionChip(
                            label: Text(s.inOneWeek),
                            onPressed: () => setSheetState(() => dueDate = dateOnly(DateTime.now().add(const Duration(days: 7)))),
                          ),
                          ActionChip(
                            label: Text(s.inTwoWeeks),
                            onPressed: () => setSheetState(() => dueDate = dateOnly(DateTime.now().add(const Duration(days: 14)))),
                          ),
                          ActionChip(
                            label: Text(s.inOneMonth),
                            onPressed: () => setSheetState(() => dueDate = dateOnly(DateTime.now().add(const Duration(days: 30)))),
                          ),
                          if (dueDate != null)
                            ActionChip(
                              avatar: const Icon(Icons.close_rounded, size: 16),
                              label: Text(s.clearDate),
                              onPressed: () => setSheetState(() => dueDate = null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: controller.text.trim().isEmpty
                            ? null
                            : () => Navigator.of(sheetContext).pop(true),
                        child: Text(s.save),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    final borrower = controller.text.trim();
    if (borrower.isEmpty) return;

    setState(() {
      _draft = _draft.copyWith(
        borrowedTo: borrower,
        borrowedAt: _draft.borrowedAt ?? DateTime.now(),
        returnDueAt: dueDate,
        clearReturnDue: dueDate == null,
      );
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final store = InventoryScope.read(context);
    final navigator = Navigator.of(context);

    var saved = _draft.copyWith(name: _nameCtrl.text.trim());
    // Klasörün adi boş kalmasin; sıralı varsayilana don. Esyadan
    // klasöre cevrildiyse taslaktaki boş ad yerine yeni sira alınır.
    if (saved.isContainer && saved.name.isEmpty) {
      saved = saved.copyWith(
        name: widget.node.name.trim().isNotEmpty
            ? widget.node.name
            : store.defaultContainerName(store.bucketKey(saved)),
      );
    }
    // Kullanıcının bu oturumda değiştirdiği resim (karşıdan gelen değişiklik değil).
    final replaced = _originalImage != saved.imagePath ? _originalImage : null;
    // Düzenleyici açıkken kayıt değişmiş olabilir (karşıdan adet, yer, ek değişikliği
    // geldi). Taslak olduğu gibi yazılmaz: o değişikliği geri alır, eski değeri de "en
    // yeni" diye herkese yayardı. Yalnızca bu oturumda yapılan değişiklikler kaydın
    // şimdiki haline uygulanır.
    final current = store.byId(saved.id);
    if (current != null) saved = applyEdits(opened: widget.node, draft: saved, current: current);
    // İşaret kayıttan önce: yeni özel kayıt bir an bile karşıya gitmesin.
    if (!store.isPrivate(saved.parentId) && _private != store.isPrivateRoot(saved.id)) {
      await store.setPrivate(saved.id, _private);
    }
    await store.commit(saved);
    // Değiştirilen resmin eskisi artık gereksiz — ama onay bekleyen bir
    // değişiklik hâlâ o yolu gösteriyorsa dosyaya dokunulmaz. (Kayıt
    // yazıldıktan sonra sorulur, yoksa eski yol hâlâ kullanımda görünürdü.)
    store.discardImage(replaced);
    // Kayıttan çıkarılan eklerin dosyaları da (aynı kural).
    store.discardFiles(_originalFiles.difference({for (final a in saved.attachments) ?a.file}));
    // İlk tarihli eşyada bildirim izni sorulur: neden istendiği o an belli.
    if ((!saved.isContainer && saved.hasDates) || saved.nextService != null) DateNotifier.instance.askOnce();
    navigator.pop(saved);
  }

  bool get _hasChanges {
    final name = _nameCtrl.text.trim();
    final originalName = (widget.isNew && widget.node.isContainer) ? '' : widget.node.name.trim();
    if (name != originalName) return true;
    if (_draft.imagePath != _originalImage) return true;
    if (_draft.attachments != widget.node.attachments) return true;
    if (_draft.kind != widget.node.kind) return true;
    if (_draft.note != widget.node.note) return true;
    if (_draft.color != widget.node.color) return true;
    if (_draft.icon != widget.node.icon) return true;
    if (_draft.locationLabel != widget.node.locationLabel) return true;
    if (_draft.lat != widget.node.lat || _draft.lng != widget.node.lng) return true;
    if (_draft.quantity != widget.node.quantity) return true;
    if (_draft.unit != widget.node.unit) return true;
    if (_draft.minQuantity != widget.node.minQuantity) return true;
    if (_draft.shelfLife != widget.node.shelfLife) return true;
    if (_draft.expiresAt != widget.node.expiresAt) return true;
    if (_draft.warranty != widget.node.warranty) return true;
    if (_draft.warrantyEndsAt != widget.node.warrantyEndsAt) return true;
    if (_draft.barcode != widget.node.barcode) return true;
    if (_draft.price != widget.node.price) return true;
    if (_draft.serial != widget.node.serial) return true;
    if (!sameField(_draft, widget.node, NodeField.service) || !sameField(_draft, widget.node, NodeField.serviced)) {
      return true;
    }
    // Vazgeçerken sorulmuyordu: yalnızca satın alma günü ya da uyarı süresi değişen taslak sessizce gidiyordu.
    if (_draft.purchasedAt != widget.node.purchasedAt || _draft.expiryWarn != widget.node.expiryWarn) return true;
    if (_draft.borrowedTo != widget.node.borrowedTo) return true;
    if (_draft.returnDueAt != widget.node.returnDueAt) return true;
    if (_draft.autoShop != widget.node.autoShop) return true;
    if (_draft.lots != widget.node.lots) return true;
    // Yer, doluluk, sorumlular ve "Yalnızca bende" de: yalnızca bunlar değişince ✕ sormadan atıyordu.
    if (_draft.parentId != widget.node.parentId || _draft.inDrawer != widget.node.inDrawer) return true;
    if (!sameField(_draft, widget.node, NodeField.full) || !sameField(_draft, widget.node, NodeField.managers)) {
      return true;
    }
    if (_private != InventoryScope.read(context).isPrivateRoot(widget.node.id)) return true;
    return false;
  }

  Future<void> _cancel() async {
    if (_hasChanges) {
      final s = AppStrings.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(s.discardChangesQuestion),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(s.keepEditing),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(s.discardChangesAction),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    // Kaydedilmeden çekilen resim diskte kalmasın (başka bir kayıt ya da
    // bekleyen değişiklik kullanıyorsa durur).
    final store = InventoryScope.read(context);
    if (_draft.imagePath != _originalImage) {
      store.discardImage(_draft.imagePath);
    }
    // Bu oturumda eklenen ek dosyaları da.
    store.discardFiles([
      for (final a in _draft.attachments)
        if (!_originalFiles.contains(a.file)) a.file,
    ]);
    Navigator.of(context).pop();
  }

  /// Büyük sayılar için adedi yazarak gir.
  Future<void> _typeQuantity() => _typeNumber(
        title: AppStrings.of(context).quantity,
        initial: _draft.quantity ?? 1,
        apply: (q) => setQuantityByLots(_draft, q, DateTime.now()),
      );

  /// En az adet de yazılarak girilebilir; 0 yazmak sınırı kaldırır.
  Future<void> _typeMinQuantity() => _typeNumber(
        title: AppStrings.of(context).fieldMinQuantity,
        initial: _draft.minQuantity ?? 1,
        apply: _withMinQuantity,
      );

  /// En az adet 1'den küçük olamaz: 0 kalınca eşya zaten "Tükenenler"de.
  Node _withMinQuantity(int q) =>
      q < 1 ? _draft.copyWith(clearMinQuantity: true) : _draft.copyWith(minQuantity: q);

  Future<void> _typeNumber({required String title, required int initial, required Node Function(int) apply}) async {
    final s = AppStrings.of(context);
    final values = await showTextPrompt(
      context,
      title: title,
      fields: [
        PromptField(
          label: title,
          initial: '$initial',
          keyboardType: TextInputType.number,
          // Yeni sayı yazılınca eskisinin yerine geçsin ("4" yazan "41" olmasın).
          selectAll: true,
        ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    final q = int.tryParse(values?.single.trim() ?? '');
    if (q == null || !mounted) return;
    setState(() => _draft = apply(q));
  }

  Future<void> _pickUnit() async {
    final s = AppStrings.of(context);
    final commonUnits = [
      s.unitPiece,
      s.unitPackage,
      s.unitKg,
      s.unitGram,
      s.unitMeter,
      s.unitCm,
      s.unitLiter,
      s.unitBox,
      s.unitPair,
      s.unitRoll,
    ];
    final choice = await showAppSheet<String>(context, (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.unit, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in commonUnits)
                    ChoiceChip(
                      label: Text(u),
                      selected: _draft.unit == u,
                      onSelected: (_) => Navigator.of(sheetContext).pop(u),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_note_rounded),
                title: Text(s.customUnit),
                subtitle: Text(s.unitHint),
                onTap: () => Navigator.of(sheetContext).pop('__custom__'),
              ),
            ],
          ),
        ),
      );
    });
    if (choice == null || !mounted) return;
    if (choice == '__custom__') {
      final values = await showTextPrompt(
        context,
        title: s.unit,
        message: s.unitHint,
        fields: [
          PromptField(label: s.unit, initial: _draft.unit ?? '', selectAll: true),
        ],
        cancelLabel: s.cancel,
        confirmLabel: s.save,
      );
      final val = Node.cleanUnit(values?.single);
      if (mounted) setState(() => _draft = _draft.copyWith(unit: val, clearUnit: val == null));
    } else {
      final val = Node.cleanUnit(choice);
      setState(() => _draft = _draft.copyWith(unit: val, clearUnit: val == null));
    }
  }

  void _setColor(Color color) {
    _colorChosen = true;
    setState(() => _draft = _draft.copyWith(color: color.toARGB32()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tones = Tones.of(context);
    final store = InventoryScope.of(context);
    final s = store.strings;
    final preview = _draft.copyWith(
      name: _nameCtrl.text.trim().isEmpty ? _draft.name : _nameCtrl.text,
    );
    final placement = store.pathLabelForParent(_draft.parentId, inDrawer: _draft.inDrawer);
    final image = AppPaths.imageFile(_draft.imagePath);
    final selectedColor = canonicalCardColor(_draft.color).toARGB32();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        appBar: ShellHeader(
          eyebrow: _draft.isContainer ? s.container : s.item,
          title: widget.isNew ? (_draft.isContainer ? s.newContainer : s.newItem) : s.editRecord,
          leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: s.cancel, onPressed: _cancel),
          actions: const [],
          trailing: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 20),
            label: Text(s.save),
          ),
        ),
        body: _EditorLayout(
          head: [
            // Canlı önizleme: kart destede nasıl görünecekse öyle.
            SizedBox(
              height: 196,
              child: NodeCard(
                node: preview,
                openPhoto: true,
                subtitle: _draft.isContainer ? s.recordCount(store.childCount(_draft.id)) : placement,
                // Ad kartın başlığında, yerinde yazılır: parmak oraya gidiyordu.
                // Boş bırakılırsa alacağı ad (klasörde sıradaki sayı, eşyada "Adsız N") silik görünür.
                titleController: _nameCtrl,
                titleHint: _draft.isContainer ? widget.node.name : _unnamedHint,
                titleAutofocus: widget.isNew && !_draft.isContainer,
                onTitleChanged: (_) => setState(() {}),
                onTitleSubmitted: _save,
                // Simgeye dokununca simge seçilir.
                onGlyph: _pickIcon,
              ),
            ),
            // Not kartın hemen altında: kartta görünen şey o (eskiden sayfanın en sonundaydı).
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: TextFormField(
                initialValue: _draft.note ?? '',
                onTapOutside: dismissKeyboard,
                maxLines: 4,
                minLines: 2,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (v) => _draft = _draft.copyWith(note: v),
                decoration: InputDecoration(labelText: s.noteOptional, alignLabelWithHint: true),
              ),
            ),
          ],
          rest: [
            // Her kayıtta bakılanlar hep açık: görünüm ve yer.
            PaperSection(
              title: s.appearance,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Tile(
                          label: _draft.hasImage ? s.replacePhoto : s.photo,
                          onTap: _pickImage,
                          child: image == null
                              ? Icon(Icons.add_a_photo_rounded, color: tones.muted)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(image, width: 52, height: 52, fit: BoxFit.cover, cacheWidth: 160),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Tile(
                          label: s.icon,
                          onTap: _pickIcon,
                          child: Icon(nodeGlyph(_draft), color: tones.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                  child: Text(s.cardColor, style: theme.textTheme.labelMedium),
                ),
                // Renkler satır içinde: tek dokunuşla, sayfa açmadan.
                SizedBox(
                  height: 52,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: kCardPalette.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      final c = kCardPalette[i];
                      final selected = c.toARGB32() == selectedColor;
                      return GestureDetector(
                        onTap: () => _setColor(c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 40,
                          height: 40,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: cardTone(c.toARGB32(), theme.brightness),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? tones.ink : tones.line,
                              width: selected ? 3 : 1,
                            ),
                          ),
                          child: selected ? Icon(Icons.check, size: 20, color: tones.ink) : null,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
            PaperSection(
              title: s.placeSection,
              children: [
                PaperRow(
                  icon: Icons.account_tree_rounded,
                  title: placement,
                  subtitle: s.placementHint,
                  onTap: _editPlacement,
                ),
                // Yeri doldu mu: yeni eşyaya yer ararken kartta görünür.
                if (_draft.isContainer)
                  PaperRow(
                    icon: _draft.isFull ? Icons.archive_rounded : Icons.archive_outlined,
                    title: s.markFull,
                    subtitle: s.fullHint,
                    tint: _draft.isFull ? tones.accent : null,
                    trailing: Switch(
                      value: _draft.isFull,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(isFull: v)),
                    ),
                  ),
                // Klasörün dünyadaki yeri (GPS).
                if (_draft.isContainer)
                  PaperRow(
                    icon: _locating ? Icons.hourglass_top_rounded : Icons.place_rounded,
                    title: _draft.hasGeo
                        ? (_draft.locationLabel ?? LocationService.format(_draft.lat!, _draft.lng!))
                        : s.gpsLocation,
                    subtitle: _draft.hasGeo
                        ? LocationService.format(_draft.lat!, _draft.lng!)
                        : s.gpsLocationHint,
                    onTap: _editGeoLocation,
                    trailing: IconButton(
                      tooltip: s.useCurrentLocation,
                      icon: const Icon(Icons.my_location_rounded),
                      onPressed: _locating ? null : _autoLocate,
                    ),
                  ),
              ],
            ),
            // Gerisi istenince açılır (bkz. [_open]); bilgisi olan açık gelir.
            // Eşya adedi: sarf malzemesi için. Klasörde yok.
            if (_shows(_Section.quantity))
              PaperSection(
                key: _sectionKeys[_Section.quantity],
                title: s.quantity,
                children: [
                  PaperRow(
                    icon: Icons.inventory_rounded,
                    title: _draft.tracksQuantity ? s.quantityShort(_draft.quantity!) : s.quantity,
                    subtitle: _draft.tracksQuantity ? s.quantityTrackedHint : s.quantityHint,
                    trailing: _QuantityField(
                      value: _draft.quantity ?? 1,
                      tracked: _draft.tracksQuantity,
                      // Paketli eşyada azalan en eski paketten, artan en yenisine (bkz. lots.dart).
                      onChanged: (q) => setState(() => _draft = setQuantityByLots(_draft, q, DateTime.now())),
                      onType: _typeQuantity,
                    ),
                  ),
                  // Azalınca alışveriş listesine: yalnızca adet tutulurken anlamlı.
                  if (_draft.tracksQuantity)
                    PaperRow(
                      icon: Icons.production_quantity_limits_rounded,
                      title: _draft.minQuantity == null ? s.minQuantityOff : s.minQuantityOn(_draft.minQuantity!),
                      subtitle: _draft.minQuantity == null
                          ? s.minQuantityOffHint
                          : s.minQuantityOnHint(_draft.minQuantity!),
                      trailing: _QuantityField(
                        value: _draft.minQuantity ?? 1,
                        tracked: _draft.minQuantity != null,
                        onChanged: (q) => setState(() {
                          // İlk dokunuş sınırı 1'de açar (soluk 1 → 2 değil).
                          _draft = _draft.minQuantity == null ? _withMinQuantity(1) : _withMinQuantity(q);
                        }),
                        onType: _typeMinQuantity,
                      ),
                    ),
                  // Ölçü birimi (ör. "kg", "adet", "paket", "lt").
                  if (_draft.tracksQuantity)
                    PaperRow(
                      icon: Icons.straighten_rounded,
                      title: s.unit,
                      subtitle: _draft.unit ?? s.unitPiece,
                      onTap: _pickUnit,
                      trailing: _draft.unit == null
                          ? null
                          : IconButton(
                              tooltip: s.clearValue,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _draft = _draft.copyWith(clearUnit: true)),
                            ),
                    ),
                  if (_draft.tracksQuantity)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(58, 0, 16, 8),
                        child: Wrap(
                          spacing: 4,
                          children: [
                            TextButton(
                              onPressed: () => setState(
                                // Adetsiz eşyada paket de olmaz: en yakın tarih eşyanın tarihi kalır.
                                () => _draft = _draft.copyWith(
                                  clearQuantity: true,
                                  clearMinQuantity: true,
                                  lots: const [],
                                  expiresAt: _draft.hasLots ? _draft.lots.first.expires : null,
                                ),
                              ),
                              child: Text(s.stopCounting),
                            ),
                            if (_draft.minQuantity != null)
                              TextButton(
                                onPressed: () => setState(() => _draft = _draft.copyWith(clearMinQuantity: true)),
                                child: Text(s.removeMinQuantity),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            // Bitince, azalınca ya da tarihi geçince listeye kendiliğinden girsin
            // mi: eşyanın kendi ayarı, varsayılan kapalı (kapalıyken önerilir).
            if (_shows(_Section.shopping))
              PaperSection(
                key: _sectionKeys[_Section.shopping],
                title: s.shoppingList,
                children: [
                  PaperRow(
                    icon: Icons.add_shopping_cart_rounded,
                    title: s.autoShopTitle,
                    subtitle: s.autoShopHint,
                    onTap: () => setState(() => _draft = _draft.copyWith(autoShop: !_draft.autoShop)),
                    trailing: Switch(
                      value: _draft.autoShop,
                      onChanged: (v) => setState(() => _draft = _draft.copyWith(autoShop: v)),
                    ),
                  ),
                ],
              ),
            // Satın alma, son kullanma, garanti: yalnızca eşyada.
            if (_shows(_Section.dates))
              KeyedSubtree(key: _sectionKeys[_Section.dates], child: _datesSection(store)),
            // Fiyat ve seri no: sigorta, taşınma ve garanti için (yalnızca eşyada).
            if (_shows(_Section.value))
              KeyedSubtree(key: _sectionKeys[_Section.value], child: _valueSection(s)),
            // Periyodik bakım ve geçmişi (alet, cihaz, araç).
            if (_shows(_Section.service))
              KeyedSubtree(key: _sectionKeys[_Section.service], child: _serviceSection(store)),
            if (_shows(_Section.attachments))
              KeyedSubtree(key: _sectionKeys[_Section.attachments], child: _attachmentsSection(s)),
            if (_shows(_Section.more))
              PaperSection(
                key: _sectionKeys[_Section.more],
                title: s.moreActions,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(s.kindLabel, style: theme.textTheme.labelMedium),
                        const SizedBox(height: 8),
                        SegmentedButton<NodeKind>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: NodeKind.item,
                              label: Text(s.item),
                              icon: Icon(glyphFor(NodeKind.item), size: 18),
                            ),
                            ButtonSegment(
                              value: NodeKind.container,
                              label: Text(s.container),
                              icon: Icon(glyphFor(NodeKind.container), size: 18),
                            ),
                          ],
                          selected: {_draft.kind},
                          onSelectionChanged: (v) {
                            if (v.single != _draft.kind) _toggleKind();
                          },
                        ),
                      ],
                    ),
                  ),
                  const PaperDivider(),
                  // Klasörü zaten özelse bu da özel; anahtar kilitli durur.
                  Builder(builder: (context) {
                    final inherited = InventoryScope.of(context).isPrivate(_draft.parentId);
                    return PaperRow(
                      icon: inherited || _private ? Icons.lock_rounded : Icons.lock_outline_rounded,
                      title: s.privateSwitchTitle,
                      subtitle: inherited ? s.privateInherited : s.privateSwitchHint,
                      tint: inherited || _private ? tones.accent : null,
                      trailing: Switch(
                        value: inherited || _private,
                        onChanged: inherited ? null : (v) => setState(() => _private = v),
                      ),
                    );
                  }),
                  const PaperDivider(),
                  PaperRow(icon: Icons.qr_code_2_rounded, title: s.qrCode, onTap: _showQr),
                  // Ürünün veya klasörün kendi barkodu: okutunca bu kayıt bulunur.
                  // Satıra dokununca elle yazılır, sağdaki düğme kamerayla okutur.
                  const PaperDivider(),
                  PaperRow(
                    icon: Icons.qr_code_scanner_rounded,
                    title: s.barcode,
                    subtitle: _draft.barcode ?? (_draft.isContainer ? s.containerBarcodeHint : s.barcodeHint),
                    onTap: _typeBarcode,
                    trailing: IconButton(
                      icon: const Icon(Icons.photo_camera_outlined),
                      tooltip: s.scanBarcode,
                      onPressed: _scanBarcode,
                    ),
                  ),
                  if (!_draft.isContainer) ...[
                    const PaperDivider(),
                    PaperRow(
                      icon: Icons.front_hand_rounded,
                      title: s.borrowedPageTitle,
                      subtitle: _draft.isBorrowed
                          ? '${_draft.borrowedTo!}${_draft.returnDueAt != null ? " · ${s.returnDueDate}: ${s.formatDate(_draft.returnDueAt!)}" : ""}'
                          : s.borrowAction,
                      onTap: _editBorrow,
                      trailing: _draft.isBorrowed
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              tooltip: s.markReturned,
                              onPressed: () => setState(() => _draft = _draft.copyWith(clearBorrow: true)),
                            )
                          : null,
                    ),
                  ],
                  if (_draft.isContainer) ?_managersRow(context),
                ],
              ),
            _moreChips(s),
          ],
        ),
      ),
    );
  }
}

/// Düzenleyicinin gövdesi. Dikeyde tek liste (önizleme, ad, bölümler); yatayda
/// iki sütun: solda önizleme ve ad sabit durur, sağda bölümler kayar. Yatayda
/// tek dar sütun iki yanda boşluk bırakıyor, önizleme hep kayıp gidiyordu.
class _EditorLayout extends StatelessWidget {
  const _EditorLayout({required this.head, required this.rest});

  final List<Widget> head;
  final List<Widget> rest;

  @override
  Widget build(BuildContext context) {
    // Tembel liste değil: bölüm sayısı az, hepsi kurulu olsun ki açılan bölüme
    // kaydırılabilsin (ekranın dışındaki satır tembel listede hiç kurulmaz).
    if (!landscapeLayout(context)) {
      return SingleChildScrollView(
        padding: readableInsets(context, const EdgeInsets.fromLTRB(0, 8, 0, 40), maxWidth: 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [...head, ...rest]),
      );
    }
    final pad = MediaQuery.paddingOf(context);
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.only(left: pad.left, right: pad.right),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: (width * 0.4).clamp(280.0, 420.0),
            child: ListView(
              padding: EdgeInsets.fromLTRB(0, 8, 0, 24 + bottomInset(context)),
              children: head,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(0, 0, 0, 40 + bottomInset(context)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rest),
            ),
          ),
        ],
      ),
    );
  }
}

/// Düzenleyicideki adet: − sayı +. Sayıya dokununca yazarak girilir.
class _QuantityField extends StatelessWidget {
  const _QuantityField({
    required this.value,
    required this.tracked,
    required this.onChanged,
    required this.onType,
  });

  final int value;
  final bool tracked;
  final ValueChanged<int> onChanged;
  final VoidCallback onType;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final s = AppStrings.of(context);
    return Container(
      decoration: BoxDecoration(color: tones.raised, borderRadius: BorderRadius.circular(22)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: s.decrease,
            icon: const Icon(Icons.remove_rounded),
            onPressed: value > 0 || !tracked ? () => onChanged(value - 1) : null,
          ),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onType,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 34),
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kDisplayFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: tracked ? tones.ink : tones.faint,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: s.increase,
            icon: const Icon(Icons.add_rounded),
            onPressed: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

/// Görünüm panelindeki büyük kutucuk (fotoğraf, simge).
class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    return Material(
      color: tones.raised,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          child: Column(
            children: [
              SizedBox(height: 52, child: Center(child: child)),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: tones.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
