import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Kartı yana kaydırınca çalışan iş: arkada beliren panelin rengi, simgesi,
/// yazısı ve bırakınca çağrılan eylem.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onAct,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onAct;
}

/// Kartı yana kaydırma, e-posta kutularındaki gibi: sola kaydırınca [left],
/// sağa kaydırınca [right] çalışır. Kart parmakla birlikte kayar, arkasından
/// eylemin paneli çıkar, eşik geçilince titrer. Eşiğe varmadan bırakılırsa
/// kart yerine döner; kapalı yönde biraz oynar ama gitmez.
///
/// Taşıma (uzun basıp sürükleme) bozulmaz: yalnızca yatay hareket dinlenir,
/// parmak kıpırdamadan beklerse jesti uzun basma kazanır.
class CardSwipe extends StatefulWidget {
  const CardSwipe({
    super.key,
    required this.child,
    required this.shape,
    this.left,
    this.right,
  });

  final Widget child;

  /// Arkadaki panel kartla aynı biçimde durur (klasör ya da fiş kartı).
  final ShapeBorder shape;

  final SwipeAction? left;
  final SwipeAction? right;

  @override
  State<CardSwipe> createState() => _CardSwipeState();
}

class _CardSwipeState extends State<CardSwipe> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 210),
  );
  Animation<double>? _run;

  /// Kartın o anki yatay kayması.
  double _dx = 0;

  /// Parmağın gittiği toplam yol (kapalı yönde kart bunun bir kısmı kadar oynar).
  double _raw = 0;
  double _width = 1;

  /// Eşik geçildi mi; titreşim bir kez olsun diye tutuluyor.
  bool _armed = false;

  /// Eylem çalıştı; kart ekranın dışında bekliyor.
  bool _acted = false;

  /// Eylemin çalışması için kart genişliğinin bu kadarı geçilmeli.
  static const double _threshold = 0.3;
  static const double _resistance = 0.22;
  static const double _maxResisted = 34;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final run = _run;
      if (run != null && mounted) setState(() => _dx = run.value);
    });
  }

  @override
  void didUpdateWidget(CardSwipe old) {
    super.didUpdateWidget(old);
    // Eylemden sonra kart hâlâ burada duruyorsa (taşınamadı ya da hemen geri
    // alındı) yerine dönsün.
    if (_acted) {
      _acted = false;
      _run = null;
      _dx = 0;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  SwipeAction? _actionFor(double dx) => dx < 0 ? widget.left : (dx > 0 ? widget.right : null);

  void _update(DragUpdateDetails d) {
    _raw += d.delta.dx;
    final open = _actionFor(_raw) != null;
    final next = open
        ? _raw
        : _raw.sign * math.min(_raw.abs() * _resistance, _maxResisted);
    final past = open && next.abs() >= _width * _threshold;
    if (past != _armed) {
      _armed = past;
      if (past) HapticFeedback.selectionClick();
    }
    setState(() => _dx = next);
  }

  void _end(DragEndDetails d) {
    final action = _actionFor(_dx);
    final v = d.velocity.pixelsPerSecond.dx;
    // Hızlı bir fiske de yeter; eşiğe kadar götürmek gerekmiyor.
    final flung = action != null && v.abs() > 850 && v.sign == _dx.sign && _dx.abs() > 24;
    _raw = 0;
    if (action != null && (_armed || flung)) {
      _armed = false;
      _commit(action);
      return;
    }
    _armed = false;
    _settle(0);
  }

  Future<void> _commit(SwipeAction action) async {
    await _settle(_dx.sign * (_width + 40));
    if (!mounted) return;
    // Eylem kaydı çoğunlukla bu seviyeden çıkarır; kart da onunla gider.
    _acted = true;
    action.onAct();
  }

  Future<void> _settle(double target) {
    _run = Tween<double>(begin: _dx, end: target).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOut),
    );
    return _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.left == null && widget.right == null) return widget.child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          _width = constraints.maxWidth;
        }
        final action = _actionFor(_dx);
        final progress = (_dx.abs() / (_width * _threshold)).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          onHorizontalDragCancel: () {
            _raw = 0;
            _armed = false;
            _settle(0);
          },
          child: Stack(
            children: [
              // Panel her zaman ağaçta: gelip gitmesi kartı yeniden kurar,
              // sürükleme başlamışsa hedefini kaybederdi.
              Positioned.fill(
                child: IgnorePointer(
                  child: action == null
                      ? const SizedBox.shrink()
                      : _SwipePanel(
                          action: action,
                          shape: widget.shape,
                          progress: progress,
                          atEnd: _dx < 0,
                        ),
                ),
              ),
              Transform.translate(offset: Offset(_dx, 0), child: widget.child),
            ],
          ),
        );
      },
    );
  }
}

/// Kartın altından çıkan renkli panel: kartla aynı biçimde, kartın gittiği
/// yönün ucunda simge ve yazı.
class _SwipePanel extends StatelessWidget {
  const _SwipePanel({
    required this.action,
    required this.shape,
    required this.progress,
    required this.atEnd,
  });

  final SwipeAction action;
  final ShapeBorder shape;

  /// 0: kart yeni kımıldadı, 1: eşik geçildi (eylem çalışır).
  final double progress;

  /// true: yazı ve simge sağ uçta (kart sola kayıyor).
  final bool atEnd;

  @override
  Widget build(BuildContext context) {
    final icon = Transform.scale(
      scale: 0.82 + 0.18 * progress,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: action.foreground.withValues(alpha: 0.16 + 0.2 * progress),
          shape: BoxShape.circle,
        ),
        child: Icon(action.icon, size: 21, color: action.foreground),
      ),
    );
    final label = Opacity(
      opacity: progress,
      child: Text(
        action.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: action.foreground,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
    // Destede kartların yalnızca üst şeridi görünür; simge de kartın başlık
    // satırının hizasında dursun ki yarısı alttaki kartın altında kalmasın.
    return Container(
      decoration: ShapeDecoration(color: action.background, shape: shape),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      alignment: atEnd ? Alignment.topRight : Alignment.topLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: atEnd
            ? [Flexible(child: label), const SizedBox(width: 12), icon]
            : [icon, const SizedBox(width: 12), Flexible(child: label)],
      ),
    );
  }
}
