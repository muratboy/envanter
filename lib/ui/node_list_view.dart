import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/strings.dart';
import '../core/transitions.dart';
import '../data/node.dart';
import '../data/settings.dart';
import '../state/inventory_store.dart';
import '../core/theme.dart';
import 'actions.dart';
import 'container_screen.dart';
import 'selection.dart';
import 'sharing/sharing_scope.dart';
import 'widgets/drag_scroll_edges.dart';
import 'widgets/entrance.dart';
import 'widgets/focus_overlay.dart';
import 'widgets/ink_art.dart';
import 'widgets/node_card.dart';
import 'widgets/stacked_card_list.dart';

/// Bir seviyedeki kartlarin destesi. Ana ekran, klasör ici ve
/// çekmece aynı govdeyi kullanır.
class NodeListView extends StatefulWidget {
  const NodeListView({
    super.key,
    required this.parentId,
    this.compact = false,
    this.highlightId,
    this.onHoverDrill,
    this.source,
    this.selection,
    this.edgeInset = 0,
  });

  /// Sağ kenardaki kulpların kapladığı pay. Liste görünümünde satırlar kenara
  /// kadar uzandığı için ⋯ düğmesi kulpların altında kalıyor, dokunuş kulba
  /// gidebiliyordu; satırlar bu kadar içeride biter. Destede kartların düğmeleri
  /// zaten içeride olduğu için kullanılmaz.
  final double edgeInset;

  /// Kabuğun toplu seçimi. Açıkken karta dokunmak onu seçer.
  final DeckSelection? selection;

  /// [Roots.home], [Roots.drawer] ya da bir klasör kimliği.
  final String parentId;

  /// Cekmecede daha küçük kartlar.
  final bool compact;

  /// Ağaçtaki bir seviye yerine verilen kayıtlar (sık kullanılanlar). Verilince
  /// gruplama ve sıralama kapanır, alt yazıda kaydın yeri yazar.
  final List<Node> Function(InventoryStore store)? source;

  /// Aramadan gelindiyse odaklanacak kart.
  final String? highlightId;

  /// Suruklerken klasör üzerinde beklenince çağrılır. Kabuk seviyeyi
  /// yerinde değiştirir; burada route acilamaz, çünkü Navigator route
  /// degisiminde aktif pointer'lari iptal edip suruklemeyi bitirir.
  final void Function(Node container)? onHoverDrill;

  @override
  State<NodeListView> createState() => _NodeListViewState();
}

class _NodeListViewState extends State<NodeListView> {
  final _listKey = GlobalKey<StackedCardListState>();
  // Kenarda kendiliğinden kaydırma da aynı denetleyiciyi kullanıyor.
  final _scroll = ScrollController();
  bool _focusScheduled = false;

  /// Son çizimdeki satır aralığı ve sütun sayısı: görünüm (deste, liste,
  /// ızgara) değişince kaydırma aynı kayıtta kalsın diye.
  double? _lastPeek;
  int _lastColumns = 1;

  /// Görünüm değişti: en üstte duran kayıt yine en üstte dursun (satır aralığı
  /// ve sütun sayısı değiştiği için aynı konum başka bir kayda denk gelirdi).
  void _keepPlace(double peek, int columns) {
    final before = _lastPeek;
    final beforeColumns = _lastColumns;
    _lastPeek = peek;
    _lastColumns = columns;
    if (before == null || (before == peek && beforeColumns == columns) || !_scroll.hasClients) return;
    // En üstteki satır → oradaki ilk kayıt → yeni düzende o kaydın satırı.
    final first = _scroll.offset / before * beforeColumns;
    final target = (first / columns).floorToDouble() * peek;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final p = _scroll.position;
      _scroll.jumpTo(target.clamp(p.minScrollExtent, p.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Bos seviyede açılan kart hangi turu başlatır: ana ekranda klasör,
  /// klasör içinde eşya.
  NodeKind get _defaultKind =>
      widget.parentId == Roots.home ? NodeKind.container : NodeKind.item;

  Future<void> _openContainer(BuildContext cardContext, Node node) async {
    await Navigator.of(cardContext).push(
      ExpandRoute(
        sourceRect: rectOf(cardContext),
        builder: (_) => ContainerScreen(containerId: node.id),
      ),
    );
  }

  /// Kart bir başka kartın kenarına bırakıldı: o sıraya girsin.
  Future<void> _onOrder(String droppedId, int index) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final dropped = store.byId(droppedId);
    if (dropped == null) return;
    // Başka bir seviyeden geldiyse haber verilir; kendi seviyesinde sıralama
    // sessizdir, sonuç zaten gözle görünür.
    final camefrom = store.bucketKey(dropped) != widget.parentId;
    store.setDragging(null);
    // Sıralı görünümde (A–Z, son eklenen...) kartın yeri sıralamadan gelir:
    // araya bırakmak elle sırayı değiştirmez. Aynı seviyedeyse nedeni söylenir
    // ("Benim sıram"a dönmek bir dokunuş); başka seviyeden geldiyse yalnızca taşınır.
    final sort = store.settings.deckSort;
    if (sort != DeckSort.manual) {
      if (!camefrom) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(
          content: Text(s.sortedNoManual(sortLabel(s, sort))),
          action: SnackBarAction(
            label: s.sortManual,
            onPressed: () => store.updateSettings(store.settings.copyWith(deckSort: DeckSort.manual)),
          ),
          persist: false,
          duration: const Duration(seconds: 5),
        ));
        return;
      }
      if (dropped.isContainer) {
        return NodeActions.dropFolder(context, folder: dropped, targetId: widget.parentId);
      }
      if (!await store.move(droppedId, widget.parentId)) return;
      HapticFeedback.selectionClick();
      NodeActions.movedNotice(messenger, store, [dropped], s.movedTo(store.nameOf(dropped), store.pathLabel(dropped.id)));
      return;
    }
    // Başka seviyeden gelen klasör bu seviyeye giriyor: kendisi mi, içindekiler mi?
    if (dropped.isContainer && camefrom) {
      return NodeActions.dropFolder(
        context,
        folder: dropped,
        targetId: widget.parentId,
        index: index,
      );
    }
    final ok = await store.moveToIndex(droppedId, widget.parentId, index);
    if (!ok) return;
    HapticFeedback.selectionClick();
    if (!camefrom) return;
    NodeActions.movedNotice(messenger, store, [dropped], s.movedTo(store.nameOf(dropped), store.pathLabel(dropped.id)));
  }

  Future<void> _onDropped(Node target, String droppedId) async {
    final store = InventoryScope.read(context);
    final s = store.strings;
    final messenger = ScaffoldMessenger.of(context);
    final dropped = store.byId(droppedId);
    if (dropped == null) return;
    store.setDragging(null);
    // Klasör bir klasöre bırakıldı: kendisi mi gitsin, içindekiler mi?
    if (dropped.isContainer) {
      return NodeActions.dropFolder(context, folder: dropped, targetId: target.id);
    }
    final ok = await store.move(droppedId, target.id);
    if (!ok) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(s.cannotMoveIntoItself), duration: const Duration(seconds: 2)));
      return;
    }
    NodeActions.movedNotice(messenger, store, [dropped], s.movedInto(store.nameOf(dropped), store.nameOf(target)));
  }

  void _scheduleHighlight(List<Node> children) {
    if (_focusScheduled || widget.highlightId == null) return;
    final index = children.indexWhere((n) => n.id == widget.highlightId);
    if (index < 0) return;
    _focusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listKey.currentState?.focusIndex(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = InventoryScope.of(context);
    // Gösterim sırası (A–Z, son eklenen...); elle sıra mağazada olduğu gibi durur.
    final children = widget.source?.call(store) ?? store.displayChildrenOf(widget.parentId);
    _scheduleHighlight(children);

    if (children.isEmpty) {
      return _EmptyStarterCard(
        kind: _defaultKind,
        parentId: widget.parentId,
        compact: widget.compact,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Liste ve ızgara: aynı deste bileşeni, üst üste binmeyen satırlarla
        // (listede sık satırlar, ızgarada yan yana kareler).
        final view = store.settings.deckView;
        final grid = view == DeckView.grid;
        final list = view != DeckView.deck;
        final inner = constraints.copyWith(maxWidth: constraints.maxWidth - widget.edgeInset);
        final layout = switch (view) {
          DeckView.grid => DeckLayout.grid(inner),
          DeckView.list => DeckLayout.list(inner),
          DeckView.deck => DeckLayout.of(constraints, compact: widget.compact),
        };
        _keepPlace(layout.peek, layout.columns);
        // Klasörler önce gelir; eşyalar ayrı bir grup olarak başlar.
        final containers = children.where((n) => n.isContainer).length;
        final mixed = widget.source == null &&
            store.settings.groupKinds &&
            containers > 0 &&
            containers < children.length;
        // Görünüm (deste ↔ liste) ya da sıralama değişince kartlar bir anda yer
        // değiştirmesin: yeni düzen aşağıdan hafifçe yerine oturur (solma yok,
        // bkz. [Entrance]).
        return Entrance(
          trigger: (view, store.settings.deckSort),
          enabled: store.draggingId == null,
          offset: const Offset(0, 14),
          child: Stack(
          children: [
            StackedCardList(
              key: _listKey,
              controller: _scroll,
              itemCount: children.length,
              columns: layout.columns,
              peek: layout.peek,
              cardHeight: layout.cardHeight,
              flat: list,
              rightInset: list ? widget.edgeInset : 0,
              columnGap: list ? 10 : 16,
              sectionGap: list ? 38 : 34,
              sectionBreak: mixed ? containers : null,
              // Etiket kartların arasındaki sabit boşlukta durur: yazı çok büyütülünce
              // sonraki kartın altında kalıyordu (bkz. kFixedTextScale).
              sectionLabel: mixed
                  ? MediaQuery.withClampedTextScaling(
                      maxScaleFactor: kFixedTextScale,
                      child: _SectionChip(label: store.strings.items, count: children.length - containers),
                    )
                  : null,
              itemBuilder: (context, index, focus) =>
                  _card(store, children[index], focus, index, layout.peek, list, grid),
            ),
            // Sürüklenen kart kenarda beklerken deste kayar; alt şerit
            // sürükleme noktalarının üstünde kalır.
            Positioned.fill(
              child: DragScrollEdges(
                controller: _scroll,
                bottomInset: MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  Widget _card(
    InventoryStore store,
    Node node,
    ValueListenable<double> focus,
    int index,
    double peek,
    bool dense,
    bool grid,
  ) {
    final selection = widget.selection;
    final selecting = selection != null && selection.active;
    return Builder(
      builder: (cardContext) => NodeCardTile(
        node: node,
        // Odak kaydırdıkça değişir; kart onu dinler (baştan kurulmaz).
        focus: 1,
        focusOf: focus,
        index: index,
        peek: peek,
        dense: dense,
        grid: grid,
        selected: selecting ? selection.contains(node.id) : null,
        // Sıralama yalnızca gerçek bir seviyede olur: sık kullanılanlar bir
        // kısayol listesi, kayıp çekmecesi ise en son kaybolana göre dizili.
        orderParent: widget.source != null || widget.parentId == Roots.lost ? null : widget.parentId,
        onOrder: _onOrder,
        subtitle: _subtitleFor(store, node),
        onTap: selecting
            ? () => selection.toggle(node.id)
            : () => node.isContainer
                ? _openContainer(cardContext, node)
                : showNodeFocus(cardContext, node),
        onMore: () => showNodeFocus(cardContext, node),
        // Adet tutulan eşya kartın üstünden − / + ile güncellenir.
        onQuantity: !node.isContainer && node.tracksQuantity
            ? (q) => NodeActions.changeQuantity(context, node, q)
            : null,
        onDropped: (id) => _onDropped(node, id),
        onHoverOpen: widget.onHoverDrill,
        onPlus: node.isContainer
            ? () => NodeActions.create(
                  cardContext,
                  parentId: node.id,
                  kind: NodeKind.item,
                  from: rectOf(cardContext),
                )
            : null,
      ),
    );
  }

  String _subtitleFor(InventoryStore store, Node node) {
    if (node.heldBy case final by?) {
      return store.strings.heldAt(SharingScope.maybeOf(context)?.memberName(by) ?? store.strings.someone);
    }
    if (node.isLost && node.parentId == null) return store.strings.lastSeenIn(store.lastSeenLabel(node));
    // Sık kullanılanlarda önemli olan kaydın nerede durduğu.
    if (widget.source != null) return store.pathLabel(node.id);
    if (node.isContainer) {
      final count = store.childCount(node.id);
      // Dolu işaretliyken "boş" yazmak kafa karıştırır; damga zaten söylüyor.
      final label = count > 0
          ? store.strings.recordCount(count)
          : (node.isFull ? '' : store.strings.empty);
      return [
        if (label.isNotEmpty) label,
        ?node.locationLabel,
      ].join(' · ');
    }
    // Eşyada son kullanma tarihi de görünsün ("SKT 12 Eki 2026").
    final expiry = node.effectiveExpiry;
    final s = store.strings;
    return [
      ?node.locationLabel,
      if (expiry != null && node.quantity != 0) s.expiryOn(s.formatDate(expiry)),
      // Farklı tarihli paketler: en yakını yazar, kaç tarih daha olduğu yanında.
      if (node.lots.length > 1 && node.quantity != 0) s.moreDates(node.lots.length - 1),
    ].join(' · ');
  }
}

/// Destenin ekrana göre ölçüleri. Dar ekranda tek sütun; tablet ya da
/// yatay telefonda kart genişliği ~320dp'nin altına düşmeyecek kadar sütun.
/// Kısa ekranda (yatay telefon) kartlar da kısalır ki odaktaki kart sığsın.
class DeckLayout {
  const DeckLayout({required this.columns, required this.cardHeight, required this.peek});

  final int columns;
  final double cardHeight;
  final double peek;

  static const double minCardWidth = 320;
  static const int maxColumns = 4;

  /// Liste görünümü: satırlar [NodeRow.height] boyunda, aralarında 6dp; geniş
  /// ekranda satır ~300dp'nin altına düşmeyecek kadar sütun.
  static DeckLayout list(BoxConstraints constraints) {
    final columns = ((constraints.maxWidth - 32 + 10) / (300 + 10)).floor().clamp(1, maxColumns);
    return DeckLayout(columns: columns, cardHeight: NodeRow.height, peek: NodeRow.height + 6);
  }

  /// Izgara görünümü: ~104dp'den dar olmayan kareler (telefonda üç, dar
  /// telefonda iki sütun), altında ad şeridi. Karenin eni desteyle aynı
  /// hesaptan çıkar ([StackedCardList]: kenar payı 16, sütun aralığı 10).
  static DeckLayout grid(BoxConstraints constraints) {
    final room = constraints.maxWidth - 32;
    final columns = ((room + gridGap) / (104 + gridGap)).floor().clamp(2, 12);
    final slot = (room - (columns - 1) * gridGap) / columns;
    final height = (slot + NodeTile.labelHeight).roundToDouble();
    return DeckLayout(columns: columns, cardHeight: height, peek: height + gridGap);
  }

  static const double gridGap = 10;

  static DeckLayout of(BoxConstraints constraints, {bool compact = false}) {
    final width = constraints.maxWidth;
    final viewport = constraints.maxHeight;
    // Yatay telefon: alan enine geniş, boyuna kısa. Kartlar kısa kalır, daha dar
    // olabilir: aynı ekrana iki kat kayıt sığar (dikeydeki boyları boşluktu).
    final short = !compact && viewport.isFinite && viewport < 420 && width > viewport;
    final minWidth = short ? 270.0 : minCardWidth;
    final columns = compact
        ? 1
        : ((width - 32 + 16) / (minWidth + 16)).floor().clamp(1, maxColumns);
    final slot = (width - 32 - (columns - 1) * 16) / columns;
    var height = compact ? 160.0 : short ? 150.0 : (slot > 420 ? 234.0 : 214.0);
    if (viewport.isFinite && !short) height = height.clamp(140.0, math.max(140.0, viewport * 0.62));
    return DeckLayout(
      columns: columns,
      cardHeight: height,
      peek: (height * (compact ? 0.475 : 0.45)).roundToDouble(),
    );
  }
}

/// Destede eşya grubunun başlığı.
class _SectionChip extends StatelessWidget {
  const _SectionChip({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    // Askılı etiket: solda ip deliği, kağıt zemin.
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
      decoration: BoxDecoration(
        color: tones.surface,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(14), right: Radius.circular(6)),
        border: Border.all(color: tones.line),
        boxShadow: [BoxShadow(color: tones.shadow.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tones.paper,
              border: Border.all(color: tones.faint, width: 1.2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: kDisplayFont,
              color: tones.ink,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(color: tones.muted, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Hicbir kayıt yokken ortada duran, artiya basilinca ilk kaydı baslatan kart.
class _EmptyStarterCard extends StatelessWidget {
  const _EmptyStarterCard({
    required this.kind,
    required this.parentId,
    required this.compact,
  });

  final NodeKind kind;
  final String parentId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tones = Tones.of(context);
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    final isContainer = kind == NodeKind.container;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Builder(
            builder: (cardContext) => InkWell(
              borderRadius: BorderRadius.circular(26),
              onTap: () => NodeActions.create(
                cardContext,
                parentId: parentId,
                kind: kind,
                from: rectOf(cardContext),
              ),
              child: DottedBorderBox(
                height: compact ? 230 : 320,
                color: tones.faint,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkArt(isContainer ? InkArtKind.box : InkArtKind.drawer, size: compact ? 92 : 124),
                      const SizedBox(height: 14),
                      Text(
                        isContainer ? s.createFirstContainer : s.addFirstItem,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isContainer ? s.createFirstContainerHint : s.addFirstItemHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: tones.accent, borderRadius: BorderRadius.circular(15)),
                        child: Icon(Icons.add_rounded, color: tones.onAccent, size: 26),
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

/// Kesikli çerçeveli kutu; "henuz boş" hissini veriyor.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({
    super.key,
    required this.child,
    required this.color,
    required this.height,
  });

  final Widget child;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    // En az [height]; büyük yazı boyutunda içerik taşmasın diye uzayabilir.
    return CustomPaint(
      painter: _DashedRectPainter(color: color),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height, minWidth: double.infinity),
        child: Center(child: child),
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(26),
    );
    final path = Path()..addRRect(rrect);
    // Tek parçayı 10 çizgi / 8 boşluk olarak parçalıyoruz.
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 10).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 8;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter old) => old.color != color;
}

/// Görünümün kullanıcıya görünen adı ve simgesi (alt çubuktaki menü, ayarlar).
String viewLabel(AppStrings s, DeckView view) => switch (view) {
      DeckView.deck => s.viewDeck,
      DeckView.list => s.viewList,
      DeckView.grid => s.viewGrid,
    };

IconData viewIcon(DeckView view) => switch (view) {
      DeckView.deck => Icons.view_agenda_outlined,
      DeckView.list => Icons.format_list_bulleted_rounded,
      DeckView.grid => Icons.grid_view_rounded,
    };

/// Sıralamanın kullanıcıya görünen adı.
String sortLabel(AppStrings s, DeckSort sort) => switch (sort) {
      DeckSort.manual => s.sortManual,
      DeckSort.name => s.sortName,
      DeckSort.newest => s.sortNewest,
      DeckSort.expiry => s.sortExpiry,
    };
