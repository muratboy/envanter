import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/inventory_store.dart';

/// Destenin üst ve alt kenarındaki iki şerit. Sürüklenen kart kenara
/// götürülüp orada tutulunca liste kendiliğinden kayar; böylece o an ekranda
/// görünmeyen bir klasörün üzerine de gidilebilir.
///
/// Şeritler bırakma kabul etmez: altlarındaki kartlar ve seviye zemini hedef
/// olmayı sürdürür, buradan yalnızca kaydırma tetiklenir.
class DragScrollEdges extends StatelessWidget {
  const DragScrollEdges({
    super.key,
    required this.controller,
    this.band = 84,
    this.bottomInset = 0,
  });

  final ScrollController controller;

  /// Kenardaki duyarlı şeridin yüksekliği.
  final double band;

  /// Alt şeridin kenardan uzaklığı: alttaki sürükleme noktaları (vazgeç, üst
  /// seviye) kendi işlerini görsün, deste onların üstünde kaysın.
  final double bottomInset;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: band,
            child: _EdgeScroll(controller: controller, up: true),
          ),
          Positioned(
            bottom: bottomInset,
            left: 0,
            right: 0,
            height: band,
            child: _EdgeScroll(controller: controller, up: false),
          ),
        ],
      );
}

class _EdgeScroll extends StatefulWidget {
  const _EdgeScroll({required this.controller, required this.up});

  final ScrollController controller;
  final bool up;

  @override
  State<_EdgeScroll> createState() => _EdgeScrollState();
}

class _EdgeScrollState extends State<_EdgeScroll> {
  Timer? _timer;
  int _ticks = 0;

  /// Kare başına kaydırma: yavaş başlar, yarım saniyede tam hıza çıkar.
  static const double _minStep = 3;
  static const double _maxStep = 13;
  static const int _rampTicks = 30;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _enter() {
    if (_timer != null) return;
    _ticks = 0;
    // Kenarda kaydırırken kartların üzerinde bekleme (içine girme) çalışmasın:
    // parmak kenarda duruyor, altından kartlar geçiyor.
    InventoryScope.read(context).edgeScrolling = true;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) => _step());
  }

  void _leave() {
    _timer?.cancel();
    _timer = null;
    if (mounted) InventoryScope.read(context).edgeScrolling = false;
  }

  void _step() {
    final c = widget.controller;
    if (!c.hasClients) return;
    _ticks++;
    final ramp = (_ticks / _rampTicks).clamp(0.0, 1.0);
    final step = (_minStep + (_maxStep - _minStep) * ramp) * (widget.up ? -1 : 1);
    final position = c.position;
    final target = (c.offset + step).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - c.offset).abs() < 0.5) return; // ucuna geldik
    c.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    // Görünür bir şey çizmez: kaydırmanın kendisi zaten geri bildirim, ayrıca
    // sürüklenen kart parmağın orasında duruyor, bir işaret altında kalırdı.
    return DragTarget<String>(
      // Hiçbir zaman kabul etmez; yalnızca üzerinde beklenmesi işe yarar.
      onWillAcceptWithDetails: (_) {
        _enter();
        return false;
      },
      onLeave: (_) => _leave(),
      builder: (context, _, _) => const SizedBox.expand(),
    );
  }
}
