import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../core/time_span.dart';

import '../../data/node.dart';
import '../../state/inventory_store.dart';
import '../actions.dart';
import '../container_screen.dart';
import '../search_page.dart';
import '../sharing/sharing_scope.dart';
import '../shell.dart';
import 'attachments.dart';
import 'date_fields.dart';
import 'node_card.dart';
import '../../data/lots.dart';
import '../../services/box_export.dart';
import '../../state/inventory_host.dart';
import 'transfer_dialog.dart';

enum _FocusAction { qr, edit, move, trash, notThere, found, full, favorite, select, private, shopping, discard, openContainer, reveal, maintenance, transfer, exportContent, borrow }

/// Uzun basınca kart öne çıkar: sag ustte kalem, sag altta kirmizi çöp
/// kutusu, ayrica QR ve ağaçta yer degistirme.
///
/// Katman seçilen eylemi geri döndürür; eylem çağıran ekranin canli
/// context'iyle çalıştırılır, boylece kapanmis route'a dokunulmaz.
Future<void> showNodeFocus(BuildContext context, Node node) async {
  final navigator = Navigator.of(context);
  // Toplu seçim yalnızca kartın durduğu destede başlar (aramada, panelde değil).
  final selectable = InventoryShell.canSelect(context, node);
  final action = await navigator.push<_FocusAction>(
    PageRouteBuilder<_FocusAction>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      barrierDismissible: true,
      barrierLabel: InventoryScope.read(context).strings.close,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _FocusLayer(nodeId: node.id, selectable: selectable),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ),
  );
  if (action == null) return;
  // Kart bu arada ağaçtan düşmüş olabilir (ör. panel kapandı); eylem yine de
  // yapılsın diye gezginin bağlamına düşülür.
  if (!context.mounted) context = navigator.context;
  if (!context.mounted) return;

  // Kart bu arada degismis olabilir; en guncel halini kullan.
  final fresh = InventoryScope.read(context).byId(node.id) ?? node;
  switch (action) {
    case _FocusAction.qr:
      NodeActions.showQr(context, fresh);
    case _FocusAction.edit:
      await NodeActions.edit(context, fresh);
    case _FocusAction.move:
      await NodeActions.moveViaTree(context, fresh);
    case _FocusAction.trash:
      await NodeActions.trash(context, fresh);
    case _FocusAction.notThere:
      await NodeActions.notThere(context, fresh);
    case _FocusAction.found:
      await NodeActions.moveViaTree(context, fresh);
    case _FocusAction.full:
      await NodeActions.toggleFull(context, fresh);
    case _FocusAction.favorite:
      await NodeActions.toggleFavorite(context, fresh);
    case _FocusAction.select:
      InventoryShell.startSelection(context, fresh);
    case _FocusAction.private:
      await NodeActions.togglePrivate(context, fresh);
    case _FocusAction.shopping:
      await NodeActions.toggleShopping(context, fresh);
    case _FocusAction.discard:
      await NodeActions.discardExpired(context, fresh);
    case _FocusAction.openContainer:
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ContainerScreen(containerId: fresh.id),
      ));
    case _FocusAction.reveal:
      revealNode(context, fresh);
    case _FocusAction.maintenance:
      await NodeActions.markMaintained(context, fresh);
    case _FocusAction.transfer:
      await showTransferDialog(context, [fresh]);
    case _FocusAction.exportContent:
      await BoxExportService.showExportSheet(context, fresh);
    case _FocusAction.borrow:
      await NodeActions.promptBorrow(context, fresh);
  }
}

class _FocusLayer extends StatefulWidget {
  const _FocusLayer({required this.nodeId, this.selectable = false});

  final String nodeId;

  /// "Seç" gösterilsin mi: kart kabuğun açık destesinde duruyor.
  final bool selectable;

  @override
  State<_FocusLayer> createState() => _FocusLayerState();
}

class _FocusLayerState extends State<_FocusLayer> {
  /// "Diğer" açıldı: seyrek kullanılanlar (QR, dolu, yalnızca bende). Liste
  /// dokuz satıra çıkmıştı; sık kullanılanlar görünür, gerisi bir dokunuş ötede.
  bool _more = false;

  String get nodeId => widget.nodeId;
  bool get selectable => widget.selectable;

  /// Ek ekleme yerinde olur, katman kapanmaz: eklenen hemen şeritte görünür.
  Future<void> _addAttachments() async {
    final store = InventoryScope.read(context);
    final before = store.byId(nodeId);
    if (before == null) return;
    final added = await pickAttachments(context, existing: before.attachments);
    if (added.isEmpty) return;
    // Seçim sürerken kayıt değişmiş olabilir (ör. karşıdan bir ek geldi).
    final node = store.byId(nodeId);
    if (node == null) return store.discardFiles([for (final a in added) a.file]);
    await store.commit(node.copyWith(attachments: [...node.attachments, ...added]));
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final node = store.byId(nodeId);
    // Kart bu arada silindiyse katmanı kapat.
    if (node == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }

    final heldBy = node.heldBy;
    final subtitle = heldBy != null
        ? s.heldAt(SharingScope.maybeOf(context)?.memberName(heldBy) ?? s.someone)
        : node.isLost && node.parentId == null
        ? s.lastSeenIn(store.lastSeenLabel(node))
        : node.isContainer
        ? '${s.recordCount(store.childCount(node.id))} · ${store.pathLabel(node.id)}'
        : store.pathLabel(node.id);

    void close(_FocusAction action) => Navigator.of(context).pop(action);
    final tones = Tones.of(context);
    // Yatay telefonda kart kısalır, tablette çok genişlemez.
    final screen = MediaQuery.sizeOf(context);
    final cardHeight = (screen.height * 0.3).clamp(150.0, 220.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: GestureDetector(
                  // Kartın ve listenin üzerine dokunmak katmanı kapatmasın.
                  onTap: () {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: cardHeight,
                        child: NodeCard(
                          node: node,
                          subtitle: subtitle,
                          margin: EdgeInsets.zero,
                          openPhoto: true,
                          onQuantity: !node.isContainer && node.tracksQuantity
                              ? (q) => NodeActions.changeQuantity(context, node, q)
                              : null,
                        ),
                      ),
                      // Not uzunsa kartta kesiliyordu: burada tam ve kopyalanabilir olarak gösterilir.
                      if (node.note != null && node.note!.trim().isNotEmpty && (node.note!.trim().length > 60 || node.note!.contains('\n'))) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: tones.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: tones.line),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: SelectableText(
                            node.note!.trim(),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                          ),
                        ),
                      ],
                      // Değer ve seri no: eşyada kendi fiyatı, klasörde içindekilerin toplamı.
                      if (_ValueFacts.shows(store, node)) ...[
                        const SizedBox(height: 10),
                        _ValueFacts(node: node),
                      ],
                      // Periyodik bakım: ne zaman, son ne zaman yapıldı; "Bakım yapıldı" tek dokunuş.
                      if (node.hasService) ...[
                        const SizedBox(height: 10),
                        _ServiceFacts(node: node, onDone: () => close(_FocusAction.maintenance)),
                      ],
                      // Ekler: kılavuz, garanti belgesi, video... dokununca açılır.
                      if (node.hasAttachments) ...[
                        const SizedBox(height: 10),
                        AttachmentStrip(attachments: node.attachments, onAdd: _addAttachments),
                        const SizedBox(height: 10),
                      ] else
                        const SizedBox(height: 14),
                      // En sık dört eylem kartın hemen altında, yan yana: menü alt
                      // alta 7–8 satırdı, en çok kullanılan da en az kullanılan da aynı
                      // boydaydı. Uzun adları ipucunda (basılı tutunca) durur.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Quick(
                              icon: Icons.edit_rounded,
                              label: s.edit,
                              tooltip: s.edit,
                              onTap: () => close(_FocusAction.edit),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _Quick(
                              icon: Icons.account_tree_rounded,
                              label: s.quickMove,
                              tooltip: s.changePlacement,
                              onTap: () => close(_FocusAction.move),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Sık girilen kayıt: sağ kenardaki kulptan tek dokunuşla açılır.
                          Expanded(
                            child: _Quick(
                              icon: store.isFavorite(node.id) ? Icons.star_rounded : Icons.star_border_rounded,
                              label: s.quickFavorite,
                              tooltip: store.isFavorite(node.id) ? s.removeFavorite : s.addFavorite,
                              tint: store.isFavorite(node.id) ? tones.accent : null,
                              onTap: () => close(_FocusAction.favorite),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Eşyada alışveriş listesi (elle eklenir); klasörde QR kod
                          // (etiketi basılıp üstüne yapıştırılan şey klasördür).
                          Expanded(
                            child: node.isContainer
                                ? _Quick(
                                    icon: Icons.qr_code_2_rounded,
                                    label: s.qrCode,
                                    tooltip: s.qrCode,
                                    onTap: () => close(_FocusAction.qr),
                                  )
                                : _Quick(
                                    icon: node.isWanted
                                        ? Icons.remove_shopping_cart_rounded
                                        : Icons.add_shopping_cart_rounded,
                                    label: node.isWanted ? s.quickShopOn : s.quickShop,
                                    tooltip: node.isWanted ? s.removeFromShopping : s.addToShopping,
                                    tint: node.isWanted ? tones.accent : null,
                                    onTap: () => close(_FocusAction.shopping),
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Ötekiler, bağlam menüsü gibi: simge ve adı yan yana.
                      Material(
                        color: tones.surface,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Klasörse "Klasörü aç", eşyaysa "Yerine git".
                            if (node.isContainer)
                              _Action(
                                icon: Icons.folder_open_rounded,
                                label: s.openContainer,
                                onTap: () => close(_FocusAction.openContainer),
                              )
                            else
                              _Action(
                                icon: Icons.my_location_rounded,
                                label: s.goToPlace,
                                onTap: () => close(_FocusAction.reveal),
                              ),
                            // Birden çok kartı birlikte taşımak, çöpe atmak ya da
                            // etiketini basmak için: bu kartla başlar.
                            if (selectable)
                              _Action(
                                icon: Icons.checklist_rounded,
                                label: s.select,
                                onTap: () => close(_FocusAction.select),
                              ),
                            // Tarihi geçen paketler atılır, kalanlar yerinde (adet tutulan eşyada).
                            if (node.tracksQuantity && expiredUnits(node, DateTime.now()) > 0)
                              _Action(
                                icon: Icons.delete_sweep_rounded,
                                label: s.discardExpiredAction(expiredUnits(node, DateTime.now())),
                                tint: tones.danger,
                                onTap: () => close(_FocusAction.discard),
                              ),
                            // Kayıpsa "yerini biliyorum", değilse "yerinde yok".
                            node.isLost
                                ? _Action(
                                    icon: Icons.where_to_vote_rounded,
                                    label: s.iKnowWhere,
                                    tint: tones.success,
                                    onTap: () => close(_FocusAction.found),
                                  )
                                : _Action(
                                    icon: Icons.travel_explore_rounded,
                                    label: s.notThere,
                                    tint: tones.lost,
                                    onTap: () => close(_FocusAction.notThere),
                                  ),
                            // Emanette ise doğrudan öne çıkar: "Ahmet'te · Geri Al / Düzenle"
                            if (!node.isContainer && node.isBorrowed)
                              _Action(
                                icon: Icons.assignment_turned_in_rounded,
                                label: '${s.markReturned} (${node.borrowedTo})',
                                tint: tones.accent,
                                onTap: () => close(_FocusAction.borrow),
                              ),
                            // Seyrek kullanılanlar yerinde açılır; katman kapanmaz.
                            if (!_more)
                              _Action(
                                icon: Icons.more_horiz_rounded,
                                label: s.moreActions,
                                trailing: Icons.expand_more_rounded,
                                onTap: () => setState(() => _more = true),
                              )
                            else ...[
                              if (!node.isContainer && !node.isBorrowed)
                                _Action(
                                  icon: Icons.front_hand_rounded,
                                  label: s.borrowAction,
                                  onTap: () => close(_FocusAction.borrow),
                                ),
                              // Klasörde QR yukarıdaki hızlı eylemlerde.
                              if (!node.isContainer)
                                _Action(
                                  icon: Icons.qr_code_2_rounded,
                                  label: s.qrCode,
                                  onTap: () => close(_FocusAction.qr),
                                ),
                              // Klasörün yeri doldu mu: yer ararken kartta görünür.
                              if (node.isContainer)
                                _Action(
                                  icon: node.isFull ? Icons.unarchive_rounded : Icons.archive_rounded,
                                  label: node.isFull ? s.markNotFull : s.markFull,
                                  onTap: () => close(_FocusAction.full),
                                ),
                              // Başka cihazlara gitmesin. Klasöründen gelen işaret
                              // burada kaldırılamaz; o yüzden satır da çıkmaz.
                              if (store.isPrivateRoot(node.id) || !store.isPrivate(node.id))
                                _Action(
                                  icon: store.isPrivateRoot(node.id)
                                      ? Icons.lock_open_rounded
                                      : Icons.lock_outline_rounded,
                                  label: store.isPrivateRoot(node.id) ? s.makeShared : s.keepPrivate,
                                  onTap: () => close(_FocusAction.private),
                                ),
                              // İlk ek buradan; ek varken şeridin sonundaki + ile.
                              if (!node.hasAttachments)
                                _Action(
                                  icon: Icons.attach_file_rounded,
                                  label: s.addAttachment,
                                  onTap: _addAttachments,
                                ),
                              if (node.isContainer)
                                _Action(
                                  icon: Icons.description_outlined,
                                  label: s.exportContent,
                                  onTap: () => close(_FocusAction.exportContent),
                                ),
                              if (LibraryScope.maybeOf(context)?.library.entries.length case final len? when len > 1)
                                _Action(
                                  icon: Icons.swap_horiz_rounded,
                                  label: s.transferToOtherInventory,
                                  onTap: () => close(_FocusAction.transfer),
                                ),
                            ],
                            Divider(height: 1, indent: 20, endIndent: 20, color: tones.line),
                            _Action(
                              icon: Icons.delete_outline_rounded,
                              label: s.moveToTrash,
                              tint: tones.danger,
                              danger: true,
                              onTap: () => close(_FocusAction.trash),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kartın altındaki hızlı eylem: simge, altında kısa adı. Uzun adı ipucunda.
class _Quick extends StatelessWidget {
  const _Quick({required this.icon, required this.label, required this.tooltip, required this.onTap, this.tint});

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final iconColor = tint ?? tones.ink;
    // Düğmeler sabit ende: yazı büyütmesi sınırlı, ad kutusu onunla birlikte uzar.
    final scale = (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, kFixedTextScale);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tones.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 21, color: iconColor),
                ),
                const SizedBox(height: 7),
                // İki satıra kadar: "Sık kullanılan" dar ekranda bölünür.
                SizedBox(
                  height: 32 * scale,
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      textScaler: TextScaler.linear(scale),
                      style: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w700, color: tones.ink),
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

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint,
    this.danger = false,
    this.trailing = Icons.chevron_right_rounded,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? tint;
  final bool danger;

  /// Sağdaki işaret: çoğunda ok, "Diğer"de aşağı ok (yerinde açılır).
  final IconData trailing;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final iconColor = tint ?? tones.ink;
    return InkWell(
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: danger ? tones.danger : tones.ink,
                  ),
                ),
              ),
              Icon(trailing, size: 20, color: tones.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Odak katmanında kartın altındaki değer bilgisi. Eşyada fiyatı (adet birden çoksa toplamı) ve
/// seri numarası (dokununca kopyalanır: sigorta formuna, servise yazılacak); klasörde
/// içindekilerin değeri. Bilgi yoksa hiç çizilmez ([shows]).
class _ValueFacts extends StatelessWidget {
  const _ValueFacts({required this.node});

  final Node node;

  static bool shows(InventoryStore store, Node node) =>
      node.isContainer ? !store.valueOf(node.id).isEmpty : (node.price != null || node.serial != null);

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    final s = store.strings;
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final rows = <Widget>[];
    Widget row(IconData icon, String text, {VoidCallback? onTap, Widget? trailing}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: tones.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
                ?trailing,
              ],
            ),
          ),
        );
    if (node.isContainer) {
      rows.add(row(Icons.sell_outlined, s.contentsValue(s.moneyTotals(store.valueOf(node.id)))));
    } else {
      final price = node.priceMoney;
      final q = node.quantity;
      if (price != null) {
        rows.add(row(
          Icons.sell_outlined,
          q == null || q == 1
              ? s.itemValue(s.money(price))
              : s.itemValue(s.valueTimes(q, s.money(price), s.money(node.value!))),
        ));
      }
      final serial = node.serial;
      if (serial != null) {
        rows.add(row(
          Icons.confirmation_number_outlined,
          '${s.serialTitle}: $serial',
          onTap: () {
            Clipboard.setData(ClipboardData(text: serial));
            ScaffoldMessenger.maybeOf(context)
              ?..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(s.serialCopied)));
          },
          trailing: Icon(Icons.copy_rounded, size: 16, color: tones.faint),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: tones.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tones.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}

/// Odak katmanında bakım bilgisi: döngü ve ne yapılacağı, sonraki bakım (gecikmişse kırmızı,
/// yaklaştıysa turuncu), son bakım ve notu; altında "Bakım yapıldı". Geçmişin tamamı
/// düzenleyicide.
class _ServiceFacts extends StatelessWidget {
  const _ServiceFacts({required this.node, required this.onDone});

  final Node node;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final s = InventoryScope.of(context).strings;
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final today = DateTime.now();
    final every = TimeSpan.parse(node.serviceEvery);
    final next = node.nextService;
    final last = node.servicedAt;
    final latest = node.serviceLog.firstOrNull;
    final tint = switch (node.serviceStateOn(today)) {
      ExpiryState.expired => tones.danger,
      ExpiryState.soon => tones.lost,
      _ => null,
    };
    Widget row(IconData icon, String text, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color ?? tones.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: color == null ? null : FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: tones.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tint ?? tones.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (every != null)
            row(Icons.autorenew_rounded, [s.serviceEveryText(every), ?node.serviceTask].join(' · ')),
          if (next != null)
            row(
              Icons.event_rounded,
              '${s.nextServiceOn(s.formatDate(next))} · ${serviceDueText(s, next, today)}',
              color: tint,
            ),
          if (last != null)
            row(
              Icons.history_rounded,
              [
                '${s.lastService}: ${s.formatDate(last)}',
                if (latest != null && latest.day == last) ?latest.note,
              ].join(' · '),
            ),
          const SizedBox(height: 6),
          FilledButton.tonalIcon(
            onPressed: onDone,
            icon: const Icon(Icons.build_circle_outlined),
            label: Text(s.maintenanceDone),
          ),
        ],
      ),
    );
  }
}
