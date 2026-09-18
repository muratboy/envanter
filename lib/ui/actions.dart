import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/time_span.dart';
import '../core/transitions.dart';
import '../data/node.dart';
import '../state/inventory_store.dart';
import 'editor_page.dart';
import 'sharing/sharing_scope.dart';
import 'widgets/qr_sheet.dart';
import 'widgets/scroll_guard.dart';
import 'widgets/tree_picker.dart';
import 'widgets/date_fields.dart';
import 'widgets/text_prompt.dart';

/// Kartlarla ilgili akislar tek yerde; hem desteden hem arama ve
/// cekmeceden aynı sekilde cagriliyor.
class NodeActions {
  /// Var olan bir kaydı duzenler.
  static Future<Node?> edit(BuildContext context, Node node, {Rect? from}) {
    return Navigator.of(context).push<Node>(
      ExpandRoute(
        sourceRect: from ?? rectOf(context),
        builder: (_) => NodeEditorPage(node: node, isNew: false),
      ),
    );
  }

  /// Verilen yerin altinda yeni kayıt başlatır. [parentId] sanal kök
  /// ([Roots.home]/[Roots.drawer]) ya da bir klasör olabilir.
  static Future<Node?> create(
    BuildContext context, {
    required String parentId,
    required NodeKind kind,
    Rect? from,
    String? barcode,
  }) {
    final store = InventoryScope.read(context);
    // [barcode]: okutulan barkod kayıtlı değildi, yeni eşya onunla başlar.
    final draft = store.draft(parentId: parentId, kind: kind).copyWith(barcode: barcode);
    return Navigator.of(context).push<Node>(
      ExpandRoute(
        sourceRect: from ?? rectOf(context),
        builder: (_) => NodeEditorPage(node: draft, isNew: true),
      ),
    );
  }

  static void showQr(BuildContext context, Node node) {
    showAppSheet(context, (_) => QrSheet(node: node));
  }

  /// Agac üzerinden yer degistirme.
  static Future<void> moveViaTree(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final target = await pickTreeTarget(context, moving: node);
    if (target == null) return;
    final ok = await store.move(node.id, target);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(s.moveNotPossible)));
      return;
    }
    movedNotice(messenger, store, [node], s.movedTo(store.nameOf(node), store.pathLabel(node.id)));
  }

  /// Kayıt taşındı: nereye gittiğini söyler; "Geri al" eski yerine ve sırasına
  /// döndürür. Parmak yanlış klasörün üstünde kalkınca kaydı arayıp bulmak
  /// gerekiyordu; toplu taşımada geri alma vardı, tek kartta yoktu.
  /// [before]: taşınanların taşınmadan önceki halleri.
  static void movedNotice(ScaffoldMessengerState messenger, InventoryStore store, List<Node> before, String text) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      action: SnackBarAction(label: store.strings.undo, onPressed: () => store.restorePlacements(before)),
      // Eylemli bildirim kendiliğinden kapanmıyor (bkz. [trash]).
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  /// Çöp kutusuna atar; geri alma suresi taniyarak.
  static Future<void> trash(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final inside = node.isContainer ? store.descendantCount(node.id) : 0;
    final name = store.nameOf(node);
    await store.moveToTrash(node.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(inside > 0
          ? s.trashedWithChildren(name, inside)
          : s.trashedSingle(name)),
      action: SnackBarAction(
        label: s.undo,
        onPressed: () => store.restore(node.id),
      ),
      // Flutter'da eylemi olan bildirim varsayılan olarak ekranda kalıyor
      // (persist = action != null). Geri alma süresi dolunca kapansın.
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  /// Klasör sürüklenip bırakıldığında soru sorulur mu? Kural tek yerde:
  /// içi dolu bir klasör **başka bir klasöre** ya da **çekmeceye** giriyorsa
  /// sorulur. Ana ekran ve kayıp çekmecesi sıradan taşımadır.
  static bool _asksOnDrop(InventoryStore store, Node folder, String targetId) =>
      store.childCount(folder.id) > 0 &&
      (targetId == Roots.drawer || !Roots.isVirtual(targetId));

  /// Bir klasör sürüklenip bırakıldı: klasörün kendisi mi gitsin, yoksa
  /// yalnızca içindekiler mi? İçindekiler seçilirse klasör boş olarak yerinde
  /// kalır. Soru gerekmiyorsa ([_asksOnDrop]) sessizce taşınır. [index]
  /// verilirse hedefte o sıraya girilir.
  static Future<void> dropFolder(
    BuildContext context, {
    required Node folder,
    required String targetId,
    int? index,
  }) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final count = store.childCount(folder.id);
    final place = switch (targetId) {
      Roots.home => s.home,
      Roots.drawer => s.drawer,
      _ => store.nameOf(store.byId(targetId) ?? folder),
    };

    final contentsOnly = !_asksOnDrop(store, folder, targetId)
        ? false
        : await showAppSheet<bool>(context, (sheetContext) {
            final theme = Theme.of(sheetContext);
            final tones = Tones.of(sheetContext);
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                    child: Text(
                      s.folderDropTitle(store.nameOf(folder)),
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: tones.raised,
                      foregroundColor: tones.ink,
                      child: const Icon(Icons.drive_file_move_rounded),
                    ),
                    title: Text(s.dropMoveFolder),
                    subtitle: Text(s.dropMoveFolderHint(place)),
                    onTap: () => Navigator.of(sheetContext).pop(false),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: tones.accent,
                      foregroundColor: tones.onAccent,
                      child: const Icon(Icons.output_rounded),
                    ),
                    title: Text(s.dropContentsOnly),
                    subtitle: Text(s.dropContentsHint(count, place)),
                    onTap: () => Navigator.of(sheetContext).pop(true),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          });
    if (contentsOnly == null || !context.mounted) return; // vazgeçildi

    if (contentsOnly) {
      // Önbellekteki liste taşımayla değişir: geri alma için kopyası.
      final before = [...store.childrenOf(folder.id)];
      final moved = await store.moveContents(folder.id, targetId, index: index);
      if (moved == 0) return;
      movedNotice(messenger, store, before, s.contentsMoved(moved, place));
      return;
    }

    final ok = index == null
        ? await store.move(folder.id, targetId)
        : await store.moveToIndex(folder.id, targetId, index);
    if (!ok) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(s.cannotMoveIntoItself), duration: const Duration(seconds: 2)));
      return;
    }
    movedNotice(messenger, store, [folder], s.movedTo(store.nameOf(folder), store.pathLabel(folder.id)));
  }

  /// Kartı yeri belirsizlerin beklediği çekmeceye alır; geri alınabilir.
  static Future<void> toDrawer(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    // Geri alınca eski yerine döner; kayıpsa yeniden kayıp olur.
    final from = store.bucketKey(node);
    final wasLost = node.isLost;
    if (!await store.move(node.id, Roots.drawer)) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.movedTo(store.nameOf(node), store.pathLabel(node.id))),
      action: SnackBarAction(
        label: s.undo,
        onPressed: () async {
          await store.move(node.id, from);
          if (wasLost) await store.markLost(node.id);
        },
      ),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  /// Kaydı sık kullanılanlara ekler ya da çıkarır (bu cihaza özel).
  static Future<void> toggleFavorite(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final name = store.nameOf(node);
    final added = await store.toggleFavorite(node.id);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(added ? s.favoriteAdded(name) : s.favoriteRemoved(name)),
      duration: const Duration(seconds: 2),
    ));
  }

  /// Alışveriş listesine ekle / listeden çıkar (kartın ⋯ menüsü).
  static Future<void> toggleShopping(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final name = store.nameOf(node);
    final add = !node.isWanted;
    await store.setWanted(node.id, add);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(add ? s.addedToShopping(name) : s.removedFromShopping(name)),
      action: SnackBarAction(label: s.undo, onPressed: () => store.setWanted(node.id, !add)),
      persist: false,
      duration: const Duration(seconds: 4),
    ));
  }

  /// Tarihi geçen paketleri atar (kartın ⋯ menüsü); kalanlar yerinde.
  static Future<void> discardExpired(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final before = node;
    final count = await store.discardExpiredUnits(node.id);
    if (count == 0) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(s.discardedExpired(store.nameOf(node), count)),
      action: SnackBarAction(label: s.undo, onPressed: () => store.undoBought(before)),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  /// Karttaki − / +. Eşya tükenir ya da en az adede inerse: "listeye
  /// kendiliğinden ekle" ayarı açıksa listeye girdiği söylenir, kapalıysa
  /// girmez, bildirim eklemeyi önerir.
  /// Art arda −/+ dokunuşları tek bildirimde toplanır: ilk dokunuştan önceki
  /// hal (geri almak için).
  static ({String id, Node before, DateTime at})? _burst;

  static Future<void> changeQuantity(BuildContext context, Node node, int quantity) async {
    if (ScrollGuard.busy) return;
    final store = InventoryScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final before = store.shoppingReason(node);
    final at = DateTime.now();
    final burst = _burst;
    final start = burst != null && burst.id == node.id && at.difference(burst.at) < const Duration(seconds: 4)
        ? burst.before
        : node;
    _burst = (id: node.id, before: start, at: at);
    await store.setQuantity(node.id, quantity);
    final fresh = store.byId(node.id);
    if (fresh == null) return;
    // Tarihli eşyaya bir tane eklendi: en yeni paketin tarihini aldı; farklıysa
    // tek dokunuşla düzeltilir (raf ömürlüde tarih bugünden hesaplandı).
    if (quantity == (node.quantity ?? 0) + 1 && fresh.shelfLife == null && fresh.lastExpiry != null) {
      final s = store.strings;
      final date = fresh.lastExpiry!;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text(s.addedWithDate(s.formatDate(date))),
        action: SnackBarAction(
          label: s.otherDate,
          onPressed: () async {
            if (!context.mounted) return;
            final picked = await pickDay(context, initial: date, help: s.newLotsDate);
            if (picked != null && picked != date) await store.redateUnits(fresh.id, 1, date, picked);
          },
        ),
        persist: false,
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    final s = store.strings;
    final name = store.nameOf(fresh);
    final now = store.shoppingReason(fresh);
    if (fresh.isWanted || now == before || (now != ShoppingReason.out && now != ShoppingReason.low)) {
      // Kartın −/+ düğmesine yanlışlıkla dokunulabiliyor: her değişiklik
      // görünür ve geri alınabilir ("Pil: 4 → 3 · Geri al").
      messenger.hideCurrentSnackBar();
      if ((start.quantity ?? 0) == (fresh.quantity ?? 0)) return;
      messenger.showSnackBar(SnackBar(
        content: Text(s.quantityChanged(name, start.quantity ?? 0, fresh.quantity ?? 0)),
        action: SnackBarAction(
          label: s.undo,
          onPressed: () {
            _burst = null;
            store.undoBought(start);
          },
        ),
        persist: false,
        duration: const Duration(seconds: 4),
      ));
      return;
    }
    final what = now == ShoppingReason.out ? s.ranOut(name) : s.runningLow(name);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(fresh.autoShop ? '$what ${s.nowOnShoppingList}' : what),
      // Kısa: bildirim satırına sığsın.
      action: fresh.autoShop
          ? null
          : SnackBarAction(label: s.addToListShort, onPressed: () => store.setWanted(fresh.id, true)),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  /// Kartın üstündeki adede dokunarak sayıyı doğrudan girme.
  static Future<void> promptQuantity(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final initial = node.quantity ?? 1;
    final values = await showTextPrompt(
      context,
      title: node.unit != null ? '${s.quantity} (${node.unit})' : s.quantity,
      fields: [
        PromptField(
          label: node.unit != null ? '${s.quantity} (${node.unit})' : s.quantity,
          initial: '$initial',
          keyboardType: TextInputType.number,
          selectAll: true,
        ),
      ],
      cancelLabel: s.cancel,
      confirmLabel: s.save,
    );
    final q = int.tryParse(values?.single.trim() ?? '');
    if (q == null || q < 0 || !context.mounted) return;
    await changeQuantity(context, node, q);
  }

  /// Bakım yapıldı (tek dokunuş): son bakım bugün, geçmişe bir satır; bildirimde sonraki
  /// bakım günü ve "Geri al". Satın alma ve son kullanma tarihlerine dokunmaz (bkz.
  /// [InventoryStore.markServiced]): ilk sürüm satın alma tarihini bugüne çekip son kullanma
  /// tarihini siliyordu, garanti de bakımla birlikte kayıyordu.
  static Future<void> markMaintained(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final before = store.byId(node.id) ?? node;
    await store.markServiced(node.id);
    final after = store.byId(node.id);
    if (after == null) return;
    final next = after.nextService;
    final name = store.nameOf(after);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(next != null ? s.maintainedWithNext(name, s.formatDate(next)) : s.maintained(name)),
      action: SnackBarAction(label: s.undo, onPressed: () => store.undoServiced(before)),
      persist: false,
      duration: const Duration(seconds: 5),
    ));
  }

  /// Yalnızca bende tut / yeniden ortak yap. Üst klasörden gelen işaret burada
  /// kaldırılamaz (klasörün kendisinden kaldırılır).
  static Future<void> togglePrivate(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final wasShared = SharingScope.maybeOf(context)?.config.isShared ?? false;
    final next = !store.isPrivateRoot(node.id);
    await store.setPrivate(node.id, next);
    final name = store.nameOf(node);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(next ? s.markedPrivate(name, wasShared: wasShared) : s.markedShared(name)),
      duration: const Duration(seconds: 4),
    ));
  }

  /// Klasörün yeri doldu / yeri var.
  static Future<void> toggleFull(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final next = !node.isFull;
    await store.setFull(node.id, next);
    final name = store.nameOf(node);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(next ? s.markedFull(name) : s.markedNotFull(name)),
      duration: const Duration(seconds: 2),
    ));
  }

  /// Eşya yerinde yok: kayıp olarak bildir ya da çöpe at.
  static Future<void> notThere(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showAppSheet<String>(context, (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(s.notThereQuestion(store.nameOf(node)), style: theme.textTheme.titleLarge),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE08A00),
                foregroundColor: Colors.white,
                child: Icon(Icons.travel_explore_rounded),
              ),
              title: Text(s.reportLost),
              subtitle: Text(s.reportLostHint),
              onTap: () => Navigator.of(sheetContext).pop('lost'),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
                child: const Icon(Icons.delete_rounded),
              ),
              title: Text(s.trashInstead),
              subtitle: Text(s.trashInsteadHint),
              onTap: () => Navigator.of(sheetContext).pop('trash'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    });
    if (choice == null || !context.mounted) return;
    if (choice == 'trash') return trash(context, node);
    final name = store.nameOf(node);
    if (!await store.markLost(node.id)) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(s.markedLost(name))));
  }

  /// Eşyayı birine emanet verir veya emanet durumunu düzenler.
  static Future<void> promptBorrow(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;

    if (node.isBorrowed) {
      final choice = await showAppSheet<String>(context, (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(store.nameOf(node), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(s.borrowedToStamp(node.borrowedTo!), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                          if (node.returnDueAt != null) ...[
                            const SizedBox(height: 2),
                            Text('${s.returnDueDate}: ${s.formatDate(node.returnDueAt!)}', style: theme.textTheme.bodySmall),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.assignment_turned_in_rounded, color: Colors.green),
                title: Text(s.markReturned),
                onTap: () => Navigator.of(sheetContext).pop('return'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(s.borrowDetailsTitle),
                onTap: () => Navigator.of(sheetContext).pop('edit'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      });
      if (choice == null || !context.mounted) return;
      if (choice == 'return') {
        return markReturned(context, node);
      }
    }

    if (!context.mounted) return;
    await _showBorrowEditSheet(context, node);
  }

  /// Eşyanın emanetten geri alındığını kaydeder.
  static Future<void> markReturned(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    await store.commit(node.copyWith(clearBorrow: true));
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(s.returnSuccess(store.nameOf(node)))));
  }

  static Future<void> _showBorrowEditSheet(BuildContext context, Node node) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: node.borrowedTo ?? '');
    DateTime? dueDate = node.returnDueAt;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final tones = Tones.of(sheetContext);
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
                        node.isBorrowed ? s.borrowDetailsTitle : s.borrowAction,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(store.nameOf(node), style: theme.textTheme.bodyMedium?.copyWith(color: tones.muted)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: !node.isBorrowed,
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

    if (confirmed != true || !context.mounted) return;
    final borrower = controller.text.trim();
    if (borrower.isEmpty) return;

    await store.commit(node.copyWith(
      borrowedTo: borrower,
      borrowedAt: node.borrowedAt ?? DateTime.now(),
      returnDueAt: dueDate,
      clearReturnDue: dueDate == null,
    ));
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(s.borrowSuccess(store.nameOf(node), borrower))));
  }
}
