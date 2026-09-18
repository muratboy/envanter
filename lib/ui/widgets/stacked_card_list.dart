import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Kartlarin birbiri üzerine bindigi deste. Parmakla yukarı/aşağı
/// kaydırdıkça odaktaki kart tumuyle açılır, digerleri altinda şerit
/// halinde bekler.
///
/// Geometri: her kart kaydırma ekseninde [peek] kadar yer kaplar ama
/// [cardHeight] kadar çizilir; odaktan sonraki kartlar `spread` kadar
/// aşağı itilerek odaktakinin tamami görünür olur.
///
/// Geniş ekranda (tablet, yatay telefon) kartlar [columns] sütuna dizilir;
/// deste etkisi o zaman satır satır işler.
class StackedCardList extends StatefulWidget {
  const StackedCardList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.peek = 96,
    this.cardHeight = 214,
    this.gap = 14,
    this.topPadding = 8,
    this.columns = 1,
    this.sidePadding = 16,
    this.columnGap = 16,
    this.sectionBreak,
    this.sectionLabel,
    this.sectionGap = 34,
    this.waveStep = 4,
    this.waveSteps = 4,
    this.controller,
    this.emptyPlaceholder,
    this.flat = false,
    this.flatTail = 120,
    this.rightInset = 0,
  });

  /// Sağ kenarda kartların girmediği ek pay (liste görünümünde kenar kulpları
  /// satırların ucuna binmesin).
  final double rightInset;

  /// Liste görünümü: kartlar üst üste binmez, satır satır alt alta durur
  /// ([peek] satır aralığıdır); odak, dalga ve tepede birikme yok. Aynı bileşen
  /// kullanılır ki sütunlar, grup etiketi, "karta git" ve sürüklemedeki ağaç
  /// biçimi iki görünümde de aynı kalsın.
  final bool flat;

  /// Düz listenin altındaki boşluk (alttaki yüzen çubuk son satırı örtmesin).
  final double flatTail;

  final int itemCount;

  /// [focus] 1.0 iken kart tam odakta, 0.0 iken destede bekliyor. Değer
  /// kaydırdıkça değişir; kart onu dinleyip yalnızca odağa bağlı parçalarını
  /// (gölge, alt satırın belirginliği) yeniler ([FocusBuilder]). Kartın tamamı
  /// kaydırma sırasında yeniden kurulmaz.
  final Widget Function(BuildContext context, int index, ValueListenable<double> focus)
  itemBuilder;

  final double peek;
  final double cardHeight;
  final double gap;
  final double topPadding;
  final int columns;
  final double sidePadding;
  final double columnGap;

  /// Bu sıradan itibaren ikinci grup başlar (klasörlerden sonra eşyalar):
  /// yeni satırdan başlar, araya [sectionGap] kadar boşluk ve [sectionLabel]
  /// girer.
  final int? sectionBreak;
  final Widget? sectionLabel;
  final double sectionGap;

  /// Ardışık satırlar dalga gibi adım adım kayar: [waveSteps] satır boyunca
  /// her satırda [waveStep] kadar sağa, sonra [waveSteps] satır sola. Hepsi aynı
  /// hizada durunca kartlar birbirinden ayrı algılanmıyor. Sütunlu düzende
  /// bütün satır birlikte kayar, sütun aralıkları bozulmaz.
  final double waveStep;
  final int waveSteps;

  final ScrollController? controller;
  final Widget? emptyPlaceholder;

  @override
  State<StackedCardList> createState() => StackedCardListState();
}

/// Destede bir satırın odağı. Kaydırma denetleyicisini dinler; değeri o anki
/// konumdan hesaplanır (saklanmaz: kaydırırken kimse bir şey "atamaz").
class _RowFocus extends ValueListenable<double> {
  const _RowFocus(this._list, this._row);

  final StackedCardListState _list;
  final int _row;

  @override
  double get value => _list._focusOf(_row);

  @override
  void addListener(VoidCallback listener) => _list._controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _list._controller.removeListener(listener);
}

/// Odağa bağlı küçük bir parçayı (gölge, saydamlık) yeniler; **yalnızca değer
/// değişince**. Destede çoğu kartın odağı kaydırırken 0'da kalır: onlar hiç
/// yeniden kurulmaz. [child] odağa bağlı olmayan gövdedir, olduğu gibi geçer.
class FocusBuilder extends StatefulWidget {
  const FocusBuilder({super.key, required this.focus, required this.builder, this.child});

  final ValueListenable<double> focus;
  final Widget Function(BuildContext context, double focus, Widget? child) builder;
  final Widget? child;

  @override
  State<FocusBuilder> createState() => _FocusBuilderState();
}

class _FocusBuilderState extends State<FocusBuilder> {
  late double _value = widget.focus.value;

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(FocusBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focus != widget.focus) {
      oldWidget.focus.removeListener(_changed);
      widget.focus.addListener(_changed);
    }
    _value = widget.focus.value;
  }

  @override
  void dispose() {
    widget.focus.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final next = widget.focus.value;
    if (next != _value && mounted) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value, widget.child);
}

class StackedCardListState extends State<StackedCardList> {
  late final ScrollController _controller =
      widget.controller ?? ScrollController();
  bool _ownsController = false;

  double get _spread => widget.flat ? 0 : widget.cardHeight - widget.peek + widget.gap;

  int get _columns => math.max(1, widget.columns);

  int? get _break {
    final b = widget.sectionBreak;
    return b != null && b > 0 && b < widget.itemCount ? b : null;
  }

  int _rowsFor(int n) => (n + _columns - 1) ~/ _columns;

  /// İkinci grubun ilk satırı.
  int? get _breakRow => _break == null ? null : _rowsFor(_break!);

  int get _rows => _break == null
      ? _rowsFor(widget.itemCount)
      : _rowsFor(_break!) + _rowsFor(widget.itemCount - _break!);

  /// Sıradaki kartın satırı ve sütunu; ikinci grup yeni satırdan başlar.
  (int, int) _slot(int i) {
    final b = _break;
    if (b == null || i < b) return (i ~/ _columns, i % _columns);
    final j = i - b;
    return (_breakRow! + j ~/ _columns, j % _columns);
  }

  /// Üçgen dalga: her satır bir önceki satırdan [waveStep] kadar kayar;
  /// [waveSteps] adım sağa, sonra [waveSteps] adım sola. İlk satır ortada.
  /// (4 adım, 4 dp: 0, +4, +8, +4, 0, -4, -8, -4, 0, ...)
  double _wave(int row) {
    if (widget.flat) return 0;
    final n = math.max(2, widget.waveSteps);
    final half = n ~/ 2;
    final phase = (row + half) % (2 * n);
    final units = phase <= n ? phase - half : n + half - phase;
    return units * widget.waveStep;
  }

  double _gapBefore(int row) =>
      _breakRow != null && row >= _breakRow! ? widget.sectionGap : 0;

  /// Kaydırırken her karede yalnızca kartların **yeri** değişir; kartın kendisi
  /// (onlarca bileşen) aynıdır. Kurulmuş kart burada saklanır ve aynı bileşen
  /// nesnesi geri verilir: Flutter aynı nesneyi yeniden kurmaz. Odak karta
  /// dinlenebilir bir değer olarak verilir ([_RowFocus]); kaydırma kartı baştan
  /// kurdurmaz.
  ///
  /// Sıra → kart. Kartın içeriği [StackedCardList.itemBuilder]'dan gelir; o da
  /// üst bileşen her kurulduğunda yenilenen bir kapanıştır. Bu yüzden üst bileşen
  /// yeniden kurulunca (kayıt, seçim, sürükleme, ayar değişti) saklananların
  /// hepsi atılır ([didUpdateWidget]).
  Map<int, Widget> _built = {};

  static const ValueListenable<double> _inFocus = AlwaysStoppedAnimation(1);

  /// [row] satırının odağı: kaydırma konumundan hesaplanır.
  double _focusOf(int row) {
    if (widget.flat) return 1;
    final offset = _controller.hasClients ? _controller.offset : 0.0;
    return (1 - (row - offset / widget.peek).abs()).clamp(0.0, 1.0).toDouble();
  }

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
  }

  @override
  void didUpdateWidget(StackedCardList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _built = {};
  }

  /// [row] satırındaki ilk kartın sırası ([_slot]'un tersi).
  int _firstOfRow(int row) {
    final breakRow = _breakRow;
    if (breakRow == null || row < breakRow) return row * _columns;
    return _break! + (row - breakRow) * _columns;
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// Bir karti destenin tepesine, tam görünür konuma getirir.
  Future<void> focusIndex(int index) async {
    if (!_controller.hasClients) return;
    final row = _slot(index).$1;
    final target = (row * widget.peek + _gapBefore(row)).clamp(
      _controller.position.minScrollExtent,
      _controller.position.maxScrollExtent,
    );
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) {
      return widget.emptyPlaceholder ?? const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxHeight;
        // Son kartin da odaga gelebilmesi için kaydırma payi bırakıyoruz.
        final tail = widget.flat
            ? widget.cardHeight + widget.flatTail
            : math.max(viewport, _spread + widget.cardHeight + 24);
        final contentHeight =
            (_rows - 1) * widget.peek +
            tail +
            (_break == null ? 0 : widget.sectionGap);
        final width = constraints.maxWidth;
        final slotWidth =
            (width -
                2 * widget.sidePadding -
                widget.rightInset -
                (_columns - 1) * widget.columnGap) /
            _columns;

        // Ekran dönünce ya da içerik kısalınca kaydırma konumu sessizce
        // düzeltilir (dinleyicilere haber verilmez); kartlar eski konuma göre
        // çizilmesin diye yeniden kurulur.
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            if (mounted) setState(() {});
            return false;
          },
          child: SingleChildScrollView(
            controller: _controller,
            physics: const ClampingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: SizedBox(
              height: contentHeight,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final offset = _controller.hasClients
                      ? _controller.offset
                      : 0.0;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: _buildCards(context, offset, viewport, slotWidth),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildCards(
    BuildContext context,
    double offset,
    double viewport,
    double slotWidth,
  ) {
    final f = offset / widget.peek;
    final children = <Widget>[];
    final kept = <int, Widget>{};

    // Yalnızca görünebilecek satırlara bakılır (binlerce kayıtta her karede
    // hepsini dolaşmamak için). Sınırlar bol tutulur; asıl eleme aşağıda,
    // eskisi gibi kart kart yapılır. Üstte: odağın üstünde birikenler 420 dp'de
    // söner (düz listede bir kart boyu). Altta: ekran + bir kart boyu.
    final above = (widget.flat ? widget.cardHeight : 420.0) + widget.sectionGap;
    final firstRow = ((offset - above) / widget.peek).floor() - 1;
    final lastRow = ((offset + viewport + widget.cardHeight) / widget.peek).ceil() + 1;
    final from = firstRow <= 0 ? 0 : math.min(widget.itemCount, _firstOfRow(firstRow));
    final to = lastRow >= _rows ? widget.itemCount : math.min(widget.itemCount, _firstOfRow(lastRow + 1));

    for (var i = from; i < to; i++) {
      final (row, column) = _slot(i);
      final revealT = ((row - f).clamp(0.0, 1.0)).toDouble();
      final reveal = Curves.easeOutCubic.transform(revealT);
      var dy = row * widget.peek + _gapBefore(row) - offset + _spread * reveal;

      // Odagin üstünde kalanlar tepede sıkışıp solarak birikir.
      var scale = 1.0;
      var opacity = 1.0;
      if (widget.flat) {
        // Düz liste: satır olduğu gibi kayar; ekranın dışındaki kurulmaz.
        if (dy < -widget.cardHeight) continue;
      } else if (dy < 0) {
        final over = -dy;
        dy = -over * 0.22;
        scale = (1 - over / 2600).clamp(0.9, 1.0);
        opacity = (1 - over / 420).clamp(0.0, 1.0);
      }

      // Gorunmeyenleri hiç kurmuyoruz.
      if (opacity <= 0.01 || dy > viewport + widget.cardHeight) continue;

      // İkinci grubun etiketi ilk kartının hemen üstünde, önceki grubun
      // kartlarının üzerinde ama kendi kartlarının altında durur.
      if (i == _break && widget.sectionLabel != null && (dy >= 0 || widget.flat)) {
        children.add(
          Positioned(
            key: const ValueKey('stack_section_label'),
            top: dy + offset + widget.topPadding - widget.sectionGap + 4,
            left: widget.sidePadding,
            child: Opacity(opacity: opacity, child: widget.sectionLabel!),
          ),
        );
      }

      children.add(
        Positioned(
          key: ValueKey('stack_slot_$i'),
          top: dy + offset + widget.topPadding,
          left: widget.sidePadding +
            column * (slotWidth + widget.columnGap) +
            _wave(row),
          width: slotWidth,
          height: widget.cardHeight,
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: _card(context, i, row, kept),
            ),
          ),
        ),
      );
    }
    // Ekrandan çıkanlar saklanmaz.
    _built = kept;
    return children;
  }

  Widget _card(BuildContext context, int i, int row, Map<int, Widget> kept) {
    // Kendi katmanında: yeri değişen kart yeniden çizilmez, yalnızca taşınır.
    return kept[i] = _built[i] ??
        RepaintBoundary(
          child: widget.itemBuilder(context, i, widget.flat ? _inFocus : _RowFocus(this, row)),
        );
  }
}
